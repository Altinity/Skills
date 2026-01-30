select event_date, level, thread_name, any(logger_name) as logger_name,
       message_format_string, count(*) as count
from   system.text_log
where  event_date > now() - interval 24 hour
  and level <= 'Warning'
group by all
order by level, thread_name, message_format_string

