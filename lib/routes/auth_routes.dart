
import 'dart:convert';

import 'package:bcrypt/bcrypt.dart';
import 'package:mysql_client/mysql_client.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../database.dart';

class AuthRoutes {
  Router get router {
    final router = Router();

    router.get('/', (Request request) {
      return Response.ok(
        jsonEncode({
          'status': 'success',
          'message': 'Auth routes are working',
        }),
        headers: {'content-type': 'application/json'},
      );
    });

    router.post('/register', (Request request) async {
      try {
        final body = await request.readAsString();
        final data = jsonDecode(body) as Map<String, dynamic>;

        final fullName = (data['full_name'] ?? '').toString().trim();
        final email = (data['email'] ?? '').toString().trim().toLowerCase();
        final phone = (data['phone'] ?? '').toString().trim();
        final password = (data['password'] ?? '').toString();

        if (fullName.isEmpty || email.isEmpty || password.isEmpty) {
          return Response(
            400,
            body: jsonEncode({
              'status': 'error',
              'message': 'Name, email, and password are required',
            }),
            headers: {'content-type': 'application/json'},
          );
        }

        if (!email.contains('@') || password.length < 8) {
          return Response(
            400,
            body: jsonEncode({
              'status': 'error',
              'message': 'Enter a valid email and a password of at least 8 characters',
            }),
            headers: {'content-type': 'application/json'},
          );
        }

        final MySQLConnection connection = await connectDatabase();
        try {
          final passwordHash = BCrypt.hashpw(
            password,
            BCrypt.gensalt(),
          );

          await connection.execute(
            'INSERT INTO users (full_name, email, phone, password_hash) '
            'VALUES (:full_name, :email, :phone, :password_hash)',
            {
              'full_name': fullName,
              'email': email,
              'phone': phone.isEmpty ? null : phone,
              'password_hash': passwordHash,
            },
          );

          return Response(
            201,
            body: jsonEncode({
              'status': 'success',
              'message': 'Registration successful',
            }),
            headers: {'content-type': 'application/json'},
          );
        } finally {
          await connection.close();
        }
      } catch (error) {
        final message = error.toString().toLowerCase();

        if (message.contains('duplicate') ||
            message.contains('unique')) {
          return Response(
            409,
            body: jsonEncode({
              'status': 'error',
              'message': 'This email is already registered',
            }),
            headers: {'content-type': 'application/json'},
          );
        }

        print('Registration error: $error');

        return Response(
          500,
          body: jsonEncode({
            'status': 'error',
            'message': 'Registration failed due to a server error',
          }),
          headers: {'content-type': 'application/json'},
        );
      }
    });

    
router.post('/login', (Request request) async {
  try {
    final body = await request.readAsString();
    final data = jsonDecode(body) as Map<String, dynamic>;

    final email =
        (data['email'] ?? '').toString().trim().toLowerCase();
    final password = (data['password'] ?? '').toString();

    if (email.isEmpty || password.isEmpty) {
      return Response(
        400,
        body: jsonEncode({
          'status': 'error',
          'message': 'Email and password are required',
        }),
        headers: {'content-type': 'application/json'},
      );
    }

    final connection = await connectDatabase();

    try {
      final result = await connection.execute(
        'SELECT id, full_name, email, password_hash '
        'FROM users WHERE email = :email',
        {'email': email},
      );

      if (result.rows.isEmpty) {
        return Response(
          401,
          body: jsonEncode({
            'status': 'error',
            'message': 'Invalid email or password',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      final user = result.rows.first.typedAssoc();
      final storedHash = user['password_hash'] as String;

      if (!BCrypt.checkpw(password, storedHash)) {
        return Response(
          401,
          body: jsonEncode({
            'status': 'error',
            'message': 'Invalid email or password',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      return Response.ok(
        jsonEncode({
          'status': 'success',
          'message': 'Login successful',
          'user': {
            'id': user['id'],
            'full_name': user['full_name'],
            'email': user['email'],
          },
        }),
        headers: {'content-type': 'application/json'},
      );
    } finally {
      await connection.close();
    }
  } catch (error) {
    print('Login error: $error');

    return Response.internalServerError(
      body: jsonEncode({
        'status': 'error',
        'message': 'Login failed due to a server error',
      }),
      headers: {'content-type': 'application/json'},
    );
  }
});
    return router;
  }
}