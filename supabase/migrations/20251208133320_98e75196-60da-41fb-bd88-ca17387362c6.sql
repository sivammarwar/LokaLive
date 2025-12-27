-- Fix function search path warnings
ALTER FUNCTION generate_room_code() SET search_path = public;
ALTER FUNCTION set_room_code() SET search_path = public;
ALTER FUNCTION process_validated_report() SET search_path = public;
ALTER FUNCTION check_membership_expiry() SET search_path = public;
ALTER FUNCTION handle_new_user() SET search_path = public;
ALTER FUNCTION set_reporter_membership_tier() SET search_path = public;
ALTER FUNCTION activate_membership(UUID, membership_tier) SET search_path = public;
ALTER FUNCTION extend_membership(UUID, membership_tier) SET search_path = public;
ALTER FUNCTION complete_transaction_and_activate() SET search_path = public;
ALTER FUNCTION cleanup_old_signals() SET search_path = public;
ALTER FUNCTION cleanup_abandoned_chess_games() SET search_path = public;
ALTER FUNCTION update_chess_game_timestamp() SET search_path = public;