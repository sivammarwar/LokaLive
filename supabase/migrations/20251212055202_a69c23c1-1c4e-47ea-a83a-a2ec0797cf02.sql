-- Create trigger for automatically setting room_code on private rooms
CREATE TRIGGER set_room_code_trigger
BEFORE INSERT ON public.rooms
FOR EACH ROW
EXECUTE FUNCTION public.set_room_code();

-- Also create trigger for processing validated reports
CREATE TRIGGER process_validated_report_trigger
AFTER UPDATE ON public.reports
FOR EACH ROW
EXECUTE FUNCTION public.process_validated_report();