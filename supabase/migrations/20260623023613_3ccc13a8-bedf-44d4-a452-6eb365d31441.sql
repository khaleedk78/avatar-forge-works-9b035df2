
-- ============ user_settings_general ============
CREATE TABLE public.user_settings_general (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  theme text NOT NULL DEFAULT 'dark',
  compact_mode boolean NOT NULL DEFAULT false,
  landing_page text NOT NULL DEFAULT '/',
  default_fps integer NOT NULL DEFAULT 16,
  default_scenes integer NOT NULL DEFAULT 10,
  default_steps integer NOT NULL DEFAULT 29,
  manual_approval boolean NOT NULL DEFAULT true,
  auto_publish boolean NOT NULL DEFAULT false,
  retry_failed boolean NOT NULL DEFAULT true,
  store_history boolean NOT NULL DEFAULT true,
  retain_rejected boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.user_settings_general TO authenticated;
GRANT ALL ON public.user_settings_general TO service_role;
ALTER TABLE public.user_settings_general ENABLE ROW LEVEL SECURITY;
CREATE POLICY "general admin only" ON public.user_settings_general
  FOR ALL TO authenticated
  USING (auth.uid() = user_id AND public.has_role(auth.uid(), 'admin'))
  WITH CHECK (auth.uid() = user_id AND public.has_role(auth.uid(), 'admin'));
CREATE TRIGGER trg_user_settings_general_updated
  BEFORE UPDATE ON public.user_settings_general
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

-- ============ publishing_defaults ============
CREATE TABLE public.publishing_defaults (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  default_visibility text NOT NULL DEFAULT 'subscribers',
  default_category text NOT NULL DEFAULT 'lifestyle',
  default_price numeric NOT NULL DEFAULT 0,
  watermark_enabled boolean NOT NULL DEFAULT true,
  auto_publish boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.publishing_defaults TO authenticated;
GRANT ALL ON public.publishing_defaults TO service_role;
ALTER TABLE public.publishing_defaults ENABLE ROW LEVEL SECURITY;
CREATE POLICY "publishing defaults admin only" ON public.publishing_defaults
  FOR ALL TO authenticated
  USING (auth.uid() = user_id AND public.has_role(auth.uid(), 'admin'))
  WITH CHECK (auth.uid() = user_id AND public.has_role(auth.uid(), 'admin'));
CREATE TRIGGER trg_publishing_defaults_updated
  BEFORE UPDATE ON public.publishing_defaults
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

-- ============ notification_settings ============
CREATE TABLE public.notification_settings (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  generation_email boolean NOT NULL DEFAULT false,
  generation_browser boolean NOT NULL DEFAULT true,
  generation_in_app boolean NOT NULL DEFAULT true,
  publishing_email boolean NOT NULL DEFAULT true,
  publishing_browser boolean NOT NULL DEFAULT true,
  publishing_in_app boolean NOT NULL DEFAULT true,
  failed_upload_email boolean NOT NULL DEFAULT true,
  failed_upload_browser boolean NOT NULL DEFAULT true,
  failed_upload_in_app boolean NOT NULL DEFAULT true,
  system_alerts_email boolean NOT NULL DEFAULT true,
  system_alerts_browser boolean NOT NULL DEFAULT false,
  system_alerts_in_app boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.notification_settings TO authenticated;
GRANT ALL ON public.notification_settings TO service_role;
ALTER TABLE public.notification_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "notifications admin only" ON public.notification_settings
  FOR ALL TO authenticated
  USING (auth.uid() = user_id AND public.has_role(auth.uid(), 'admin'))
  WITH CHECK (auth.uid() = user_id AND public.has_role(auth.uid(), 'admin'));
CREATE TRIGGER trg_notification_settings_updated
  BEFORE UPDATE ON public.notification_settings
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

-- ============ sync_settings ============
CREATE TABLE public.sync_settings (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  auto_sync boolean NOT NULL DEFAULT true,
  sync_interval_minutes integer NOT NULL DEFAULT 15,
  retry_uploads boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.sync_settings TO authenticated;
GRANT ALL ON public.sync_settings TO service_role;
ALTER TABLE public.sync_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "sync settings admin only" ON public.sync_settings
  FOR ALL TO authenticated
  USING (auth.uid() = user_id AND public.has_role(auth.uid(), 'admin'))
  WITH CHECK (auth.uid() = user_id AND public.has_role(auth.uid(), 'admin'));
CREATE TRIGGER trg_sync_settings_updated
  BEFORE UPDATE ON public.sync_settings
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();
