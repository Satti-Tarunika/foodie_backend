
import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_cors_headers/shelf_cors_headers.dart';

import '../lib/routes/auth_routes.dart';
import '../lib/database.dart';

Future<void> main() async {
  try {
    final database = await connectDatabase();

    final router = Router();

    router.mount('/auth/', AuthRoutes().router.call);

    router.get('/', (Request request) {
      return Response.ok(
        jsonEncode({
          'status': 'success',
          'message': 'Welcome to Foodie API',
        }),
        headers: {'content-type': 'application/json'},
      );
    });

    router.get('/health', (Request request) {
      return Response.ok(
        jsonEncode({
          'status': 'success',
          'message': 'Foodie backend is running',
          'database': 'connected',
        }),
        headers: {'content-type': 'application/json'},
      );
    });

    final handler = Pipeline()
        .addMiddleware(corsHeaders())
        .addHandler(router.call);

    final server = await io.serve(
      handler,
      '127.0.0.1',
      8080,
    );

    print('Foodie API: http://127.0.0.1:8080');

    database.onClose(() {
      print('MySQL connection closed.');
    });
  } catch (error) {
    print('Backend startup failed: $error');
  }
}