import 'package:barcode_scan2/barcode_scan2.dart';

class BarcodeService {
  static Future<String?> scanBarcode() async {
    try {
      final result = await BarcodeScanner.scan();
      return result.rawContent.isNotEmpty ? result.rawContent : null;
    } catch (e) {
      print('Error scanning barcode: $e');
      return null;
    }
  }
}
