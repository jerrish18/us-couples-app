
alter policy couple_media_read on storage.objects using
(bucket_id='couple-media' and exists(select 1 from public.couples c
 where c.id::text=(storage.foldername(storage.objects.name))[1] and (select auth.uid()) in(c.owner_id,c.partner_id)));
alter policy couple_media_upload on storage.objects with check
(bucket_id='couple-media' and (storage.foldername(storage.objects.name))[2]=(select auth.uid())::text and
 exists(select 1 from public.couples c where c.id::text=(storage.foldername(storage.objects.name))[1]
 and (select auth.uid()) in(c.owner_id,c.partner_id)));
alter policy couple_media_delete on storage.objects using
(bucket_id='couple-media' and exists(select 1 from public.couples c
 where c.id::text=(storage.foldername(storage.objects.name))[1] and (select auth.uid()) in(c.owner_id,c.partner_id)));
