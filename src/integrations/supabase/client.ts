// Pinned to the external Supabase project for Lila Studio (ref ixkzdnowlbjeiwqzfctu).
// This is the single source of truth for auth, storage, edge functions, and the
// database. Values are hardcoded (and mirrored in .env / supabase/config.toml) so
// an accidental .env regeneration can't silently repoint the app and break auth.
import { createClient } from '@supabase/supabase-js';
import type { Database } from './types';

const SUPABASE_URL = 'https://ixkzdnowlbjeiwqzfctu.supabase.co';
const SUPABASE_PUBLISHABLE_KEY = 'sb_publishable_b_go-ZVyLa0NLL7BqZFVzg_2hNG7yEd';

function createSupabaseClient() {
  return createClient<Database>(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, {
    auth: {
      storage: typeof window !== 'undefined' ? localStorage : undefined,
      persistSession: true,
      autoRefreshToken: true,
    }
  });
}

let _supabase: ReturnType<typeof createSupabaseClient> | undefined;

// Import the supabase client like this:
// import { supabase } from "@/integrations/supabase/client";
export const supabase = new Proxy({} as ReturnType<typeof createSupabaseClient>, {
  get(_, prop, receiver) {
    if (!_supabase) _supabase = createSupabaseClient();
    return Reflect.get(_supabase, prop, receiver);
  },
});

