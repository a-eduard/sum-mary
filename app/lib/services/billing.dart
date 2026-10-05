import 'dart:io';

import 'package:flutter_rustore_pay/api/flutter_rustore_pay_client.dart';
import 'package:flutter_rustore_pay/model/purchase_availability.dart';
import 'package:flutter_rustore_pay/model/ru_store_exception.dart';

import '../config.dart';
import 'api.dart';

/// Подписка через RuStore Pay SDK (только Android).
class Billing {
  static bool get supported => Platform.isAndroid;

  static Future<bool> available() async {
    if (!supported) return false;
    try {
      final r = await RuStorePayClient.instance.purchaseInteractor.getPurchaseAvailability();
      return r is Available;
    } catch (_) {
      return false;
    }
  }

  /// Цена подписки для экрана оплаты, например «299 ₽».
  static Future<String?> priceLabel() async {
    if (!supported) return null;
    try {
      final products = await RuStorePayClient.instance.productInteractor.getProducts([AppConfig.proProductId]);
      return products.isEmpty ? null : products.first.amountLabel;
    } catch (_) {
      return null;
    }
  }

  /// Покупка. Возвращает true, если оплата прошла и сервер подтвердил подписку.
  static Future<bool> buyPro({required String userId, String? email}) async {
    try {
      final res = await RuStorePayClient.instance.purchaseInteractor.purchase(
        AppConfig.proProductId,
        appUserId: userId,
        appUserEmail: email,
      );
      await Api.confirmPurchase(res.purchaseId, res.productId);
      return true;
    } on RuStorePurchaseCancelledException {
      return false;
    }
  }
}
