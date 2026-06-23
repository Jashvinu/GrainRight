delete from public.farm_timeline_events
where event_type in ('farm_alert_refresh', 'crop_lifecycle_advice');
