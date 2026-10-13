import 'dart:convert';

import 'package:dotenv/dotenv.dart';
import 'package:mysql_client/mysql_client.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';

late MySQLConnection db;

Response jsonResponse(
  Object body, {
  int status = 200,
}) {
  return Response(
    status,
    body: jsonEncode(body),
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'access-control-allow-origin': '*',
      'access-control-allow-headers': 'Content-Type',
      'access-control-allow-methods': 'GET, POST, OPTIONS',
    },
  );
}

Future<Response> placeOrder(Request request) async {
  try {
    final body = jsonDecode(await request.readAsString());

    if (body is! Map<String, dynamic>) {
      return jsonResponse(
        {'error': 'Request body must be a JSON object'},
        status: 400,
      );
    }

    final userId = int.tryParse('${body['userId'] ?? ''}');
    final address = body['deliveryAddress']?.toString().trim();
    final rawItems = body['items'];
    final paymentMethod = body['paymentMethod']?.toString() ?? 'COD';

    if (userId == null ||
        address == null ||
        address.isEmpty ||
        rawItems is! List ||
        rawItems.isEmpty) {
      return jsonResponse({
        'error': 'Provide userId, deliveryAddress, and at least one item',
      }, status: 400);
    }

    if (paymentMethod != 'COD') {
      return jsonResponse({
        'error': 'Only COD is enabled in this API version',
      }, status: 400);
    }

    // Confirm the customer exists.
    final userResult = await db.execute(
      'SELECT id FROM users WHERE id = :id',
      {'id': userId},
    );

    if (userResult.rows.isEmpty) {
      return jsonResponse({
        'error': 'User not found. Provide an existing userId.',
      }, status: 400);
    }

    // Validate items and calculate prices from the database.
    final validatedItems = <Map<String, dynamic>>[];
    double subtotal = 0;

    for (final item in rawItems) {
      if (item is! Map) {
        return jsonResponse(
          {'error': 'Each item must contain foodId and quantity'},
          status: 400,
        );
      }

      final foodId = int.tryParse('${item['foodId'] ?? ''}');
      final quantity = int.tryParse('${item['quantity'] ?? ''}');

      if (foodId == null || quantity == null || quantity < 1 ||
          quantity > 100) {
        return jsonResponse(
          {'error': 'Invalid foodId or quantity'},
          status: 400,
        );
      }

      final foodResult = await db.execute(
        'SELECT id, name, price FROM food_items '
        'WHERE id = :id AND is_available = 1',
        {'id': foodId},
      );

      if (foodResult.rows.isEmpty) {
        return jsonResponse({
          'error': 'Food item $foodId is unavailable or does not exist',
        }, status: 400);
      }

      final food = foodResult.rows.first;
      final name = food.colByName('name')!;
      final price = double.parse(food.colByName('price')!);
      final lineTotal = price * quantity;

      subtotal += lineTotal;

      validatedItems.add({
        'foodId': foodId,
        'name': name,
        'quantity': quantity,
        'price': price,
      });
    }

    const deliveryFee = 40.0;
    final total = subtotal + deliveryFee;

    // Save the order and related records together.
    final orderId = await db.transactional((tx) async {
      final orderResult = await tx.execute(
        'INSERT INTO orders '
        '(user_id, delivery_address, subtotal, delivery_fee, '
        'total_amount, payment_method, status) '
        'VALUES (:userId, :address, :subtotal, :fee, :total, '
        ':method, :status)',
        {
          'userId': userId,
          'address': address,
          'subtotal': subtotal.toStringAsFixed(2),
          'fee': deliveryFee.toStringAsFixed(2),
          'total': total.toStringAsFixed(2),
          'method': 'COD',
          'status': 'Pending',
        },
      );

      final newOrderId = orderResult.lastInsertID;

      for (final item in validatedItems) {
        await tx.execute(
          'INSERT INTO order_items '
          '(order_id, food_id, food_name, quantity, unit_price) '
          'VALUES (:orderId, :foodId, :name, :quantity, :price)',
          {
            'orderId': newOrderId,
            'foodId': item['foodId'],
            'name': item['name'],
            'quantity': item['quantity'],
            'price': (item['price'] as double).toStringAsFixed(2),
          },
        );
      }

      await tx.execute(
        'INSERT INTO deliveries (order_id, status) '
        'VALUES (:orderId, :status)',
        {
          'orderId': newOrderId,
          'status': 'Assigned',
        },
      );

      return newOrderId;
    });

    return jsonResponse({
      'success': true,
      'message': 'COD order placed successfully',
      'orderId': orderId,
      'paymentMethod': 'COD',
      'paymentStatus': 'Pending',
      'subtotal': subtotal.toStringAsFixed(2),
      'deliveryFee': deliveryFee.toStringAsFixed(2),
      'totalAmount': total.toStringAsFixed(2),
      'items': validatedItems,
    }, status: 201);
  } catch (e) {
    print('Place order error: $e');
    return jsonResponse({
      'error': 'Unable to place order. Check backend logs.',
    }, status: 500);
  }
}

Future<void> main() async {
  final env = DotEnv()..load();

  db = await MySQLConnection.createConnection(
    host: env['DB_HOST'] ?? '127.0.0.1',
    port: int.parse(env['DB_PORT'] ?? '3306'),
    userName: env['DB_USER'] ?? 'foodie_app',
    password: env['DB_PASSWORD'] ?? '',
    databaseName: env['DB_NAME'] ?? 'foodie_db',
    secure: true,
  );

  await db.connect();
  print('MySQL connected successfully!');

  final router = Router();

  router.get('/', (Request request) {
    return jsonResponse({
      'message': 'Foodie backend is running',
    });
  });

  router.post('/api/orders', placeOrder);

  router.options('/<ignored|.*>', (Request request) {
    return Response.ok('', headers: {
      'access-control-allow-origin': '*',
      'access-control-allow-headers': 'Content-Type',
      'access-control-allow-methods': 'GET, POST, OPTIONS',
    });
  });

  final server = await io.serve(router.call, '0.0.0.0', 8080);
  print('Foodie API running on port ${server.port}');
}