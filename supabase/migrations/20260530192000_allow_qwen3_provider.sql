alter table public.farmer_ai_plans
drop constraint if exists farmer_ai_plans_provider_check;
alter table public.farmer_ai_plans
add constraint farmer_ai_plans_provider_check
check (provider in ('gemini', 'qwen', 'qwen3', 'deepseek', 'fallback'));
