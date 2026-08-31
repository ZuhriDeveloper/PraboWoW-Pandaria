#!/bin/bash
# Berjalan SEKALI, saat volume data mysql masih kosong (image resmi menjalankan
# semua isi /docker-entrypoint-initdb.d/ pada saat itu).
#
# Kenapa perlu: DatabaseSetup milik core bisa mengisi database kosong tapi tidak
# bisa MEMBUAT-nya -- image mysql hanya memberi hak MYSQL_USER pada satu
# MYSQL_DATABASE, dan memberi core login root justru lebih buruk. Jadi ketiga
# database dibuat dan di-grant di sini.
#
# TIGA database, bukan empat: `hotfixes` itu khas Cataclysm (HotfixDatabaseInfo)
# dan tidak ada di SkyFire 5.4.8.
#
# utf8mb3, bukan utf8mb4: seluruh dump SkyFire (auth_database.sql,
# characters_database.sql, dump world) dibuat dengan utf8/utf8_general_ci.
# Mengganti ke utf8mb4 mengubah panjang index dan merusak import.
set -euo pipefail

for db in auth world characters; do
    mysql --protocol=socket -uroot -p"$MYSQL_ROOT_PASSWORD" <<-SQL
		CREATE DATABASE IF NOT EXISTS \`${db}\`
		    DEFAULT CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci;
		GRANT ALL PRIVILEGES ON \`${db}\`.* TO '${MYSQL_USER}'@'%';
	SQL
done

# sql/base/stored_procs.sql membuat stored procedure di database world.
mysql --protocol=socket -uroot -p"$MYSQL_ROOT_PASSWORD" <<-SQL
	GRANT CREATE ROUTINE, ALTER ROUTINE, EXECUTE ON \`world\`.*      TO '${MYSQL_USER}'@'%';
	GRANT CREATE ROUTINE, ALTER ROUTINE, EXECUTE ON \`characters\`.* TO '${MYSQL_USER}'@'%';
	FLUSH PRIVILEGES;
SQL

echo "[init] auth, world, characters dibuat untuk user '${MYSQL_USER}' (utf8mb3)"
