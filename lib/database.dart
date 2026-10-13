import 'package:dotenv/dotenv.dart';
import 'package:mysql_client/mysql_client.dart';

final env = DotEnv(includePlatformEnvironment: true)..load();

Future<MySQLConnection> connectDatabase() async {
  final connection = await MySQLConnection.createConnection(
    host: env['DB_HOST'] ?? '127.0.0.1',
    port: int.parse(env['DB_PORT'] ?? '3306'),
    userName: env['DB_USER'] ?? 'root',
    password: env['DB_PASSWORD'] ?? '',
    databaseName: env['DB_NAME'] ?? 'foodie_db',
    secure: true,
  );

  await connection.connect();

  await connection.execute('SELECT 1');

  print('Connected to foodie_db successfully!');

  return connection;
}