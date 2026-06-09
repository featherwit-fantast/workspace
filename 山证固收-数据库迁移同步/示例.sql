#增量	
mysqldump -h10.6.4.195 -P3306 -uficc -p'Gongxifacai@2023' \
  --skip-add-drop-table \
  --no-create-info \
  --skip-triggers \
  --compact \
  --databases yltrs_ylcms \
  --tables trade \
  --where="OptDate > '2026-04-28 14:24:44'" \
  >  /backup/binlog-$(date +%F_%H%M%S).sql