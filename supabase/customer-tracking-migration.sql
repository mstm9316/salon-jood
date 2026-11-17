-- تحديث متابعة الزبائن لصالون جود
-- نفّذ مرة واحدة من Supabase > SQL Editor > New query

ALTER TABLE public.bookings
  ADD COLUMN IF NOT EXISTS tracking_code text,
  ADD COLUMN IF NOT EXISTS proposed_date date,
  ADD COLUMN IF NOT EXISTS proposed_start_time time,
  ADD COLUMN IF NOT EXISTS manager_note text;

ALTER TABLE public.queue_entries
  ADD COLUMN IF NOT EXISTS tracking_code text;

-- السماح بحالة اقتراح موعد من المدير
ALTER TABLE public.bookings DROP CONSTRAINT IF EXISTS bookings_status_check;
ALTER TABLE public.bookings ADD CONSTRAINT bookings_status_check
  CHECK (status IN ('pending','proposed','confirmed','rejected','cancelled','completed'));

-- الانضمام للدور مع رمز متابعة خاص
DROP FUNCTION IF EXISTS public.join_queue(text,text,uuid);
DROP FUNCTION IF EXISTS public.join_queue(text,text,uuid,text);
CREATE FUNCTION public.join_queue(
  p_customer_name text,
  p_customer_phone text,
  p_service_id uuid,
  p_tracking_code text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_ticket bigint;
BEGIN
  IF length(trim(p_customer_name)) < 2 OR length(trim(p_customer_phone)) < 6 THEN
    RAISE EXCEPTION 'يرجى إدخال اسم ورقم هاتف صحيحين';
  END IF;
  IF p_tracking_code !~ '^[0-9]{8}$' THEN
    RAISE EXCEPTION 'رمز المتابعة غير صالح';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.services WHERE id=p_service_id AND active=true) THEN
    RAISE EXCEPTION 'الخدمة غير متاحة';
  END IF;
  INSERT INTO public.queue_entries(customer_name,customer_phone,service_id,tracking_code)
  VALUES(trim(p_customer_name),trim(p_customer_phone),p_service_id,p_tracking_code)
  RETURNING ticket_number INTO v_ticket;
  RETURN jsonb_build_object('ticket_number',v_ticket,'tracking_code',p_tracking_code);
END;
$$;
GRANT EXECUTE ON FUNCTION public.join_queue(text,text,uuid,text) TO anon, authenticated;

-- إرجاع طلبات هذا الزبون فقط عند تطابق الهاتف ورمز المتابعة
CREATE OR REPLACE FUNCTION public.customer_tracking(p_customer_phone text, p_tracking_code text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_bookings jsonb; v_queue jsonb;
BEGIN
  IF length(trim(p_customer_phone)) < 6 OR p_tracking_code !~ '^[0-9]{8}$' THEN
    RAISE EXCEPTION 'رقم الهاتف أو رمز المتابعة غير صحيح';
  END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id',b.id,'customer_name',b.customer_name,'booking_date',b.booking_date,
    'start_time',b.start_time,'end_time',b.end_time,'status',b.status,
    'proposed_date',b.proposed_date,'proposed_start_time',b.proposed_start_time,
    'manager_note',b.manager_note,'service_name',s.name
  ) ORDER BY b.created_at DESC),'[]'::jsonb)
  INTO v_bookings
  FROM public.bookings b LEFT JOIN public.services s ON s.id=b.service_id
  WHERE b.customer_phone=trim(p_customer_phone) AND b.tracking_code=p_tracking_code;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id',q.id,'ticket_number',q.ticket_number,'status',q.status,
    'created_at',q.created_at,'service_name',s.name,
    'queue_total',(SELECT count(*) FROM public.queue_entries allq WHERE allq.status IN ('waiting','called','serving')),
    'queue_position',CASE WHEN q.status IN ('waiting','called','serving') THEN
      (SELECT count(*) FROM public.queue_entries earlier
       WHERE earlier.status IN ('waiting','called','serving')
         AND (earlier.created_at < q.created_at OR (earlier.created_at=q.created_at AND earlier.ticket_number<=q.ticket_number)))
      ELSE 0 END,
    'estimated_wait_minutes',CASE WHEN q.status='waiting' THEN
      GREATEST(0,(SELECT count(*)-1 FROM public.queue_entries earlier
       WHERE earlier.status IN ('waiting','called','serving')
         AND (earlier.created_at < q.created_at OR (earlier.created_at=q.created_at AND earlier.ticket_number<q.ticket_number))) * COALESCE(s.duration_minutes,30))
      WHEN q.status='called' THEN 0 ELSE NULL END
  ) ORDER BY q.created_at DESC),'[]'::jsonb)
  INTO v_queue
  FROM public.queue_entries q LEFT JOIN public.services s ON s.id=q.service_id
  WHERE q.customer_phone=trim(p_customer_phone) AND q.tracking_code=p_tracking_code;

  IF v_bookings='[]'::jsonb AND v_queue='[]'::jsonb THEN
    RETURN jsonb_build_object('found',false,'bookings','[]'::jsonb,'queue','[]'::jsonb);
  END IF;
  RETURN jsonb_build_object('found',true,'bookings',v_bookings,'queue',v_queue);
END;
$$;
GRANT EXECUTE ON FUNCTION public.customer_tracking(text,text) TO anon, authenticated;

-- قبول أو رفض الموعد البديل من صاحب رمز المتابعة
CREATE OR REPLACE FUNCTION public.respond_booking_proposal(
  p_booking_id uuid, p_customer_phone text, p_tracking_code text, p_accept boolean
) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_duration integer;
BEGIN
  IF p_accept THEN
    SELECT s.duration_minutes INTO v_duration
    FROM public.bookings b JOIN public.services s ON s.id=b.service_id
    WHERE b.id=p_booking_id AND b.customer_phone=trim(p_customer_phone)
      AND b.tracking_code=p_tracking_code AND b.status='proposed'
      AND b.proposed_date IS NOT NULL AND b.proposed_start_time IS NOT NULL;
    IF v_duration IS NULL THEN RETURN false; END IF;
    UPDATE public.bookings b SET
      booking_date=b.proposed_date,
      start_time=b.proposed_start_time,
      end_time=(b.proposed_start_time + make_interval(mins=>v_duration))::time,
      proposed_date=NULL, proposed_start_time=NULL, status='confirmed'
    WHERE b.id=p_booking_id AND b.customer_phone=trim(p_customer_phone)
      AND b.tracking_code=p_tracking_code AND b.status='proposed';
  ELSE
    UPDATE public.bookings SET proposed_date=NULL, proposed_start_time=NULL,
      status='pending', manager_note=COALESCE(manager_note,'')
    WHERE id=p_booking_id AND customer_phone=trim(p_customer_phone)
      AND tracking_code=p_tracking_code AND status='proposed';
  END IF;
  RETURN FOUND;
END;
$$;
GRANT EXECUTE ON FUNCTION public.respond_booking_proposal(uuid,text,text,boolean) TO anon, authenticated;
