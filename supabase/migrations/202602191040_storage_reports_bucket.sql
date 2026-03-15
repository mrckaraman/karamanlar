-- Ensure Storage bucket exists for generated reports
-- Bucket: reports (private)

insert into storage.buckets (id, name, public)
values ('reports', 'reports', false)
on conflict (id) do nothing;

notify pgrst, 'reload schema';
