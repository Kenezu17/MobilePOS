import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'firestore_service.dart';
import 'api_service.dart';
import 'barcode_scan.dart';
import 'app_settings.dart';

// ── Coffee palette (light) ──────────────────────────────────────
class _Coffee {
  static const espresso   = Color(0xFF1C0F0A);   // near-black brown
  static const roast      = Color(0xFF3B1F0E);   // deep roast
  static const mocha      = Color(0xFF6B3A23);   // mid brown
  static const caramel    = Color(0xFFC07941);   // warm caramel accent
  static const latte      = Color(0xFFE8CFA8);   // creamy latte
  static const cream      = Color(0xFFF5ECD7);   // warm cream bg
  static const foam       = Color(0xFFFAF3E6);   // milk foam surface
  static const biscotti   = Color(0xFFD4A96A);   // biscotti tan
  static const error      = Color(0xFFB84040);   // warm red for errors
}

// ── Dark palette ────────────────────────────────────────────────
class _Dark {
  static const bg        = Color(0xFF1A0F0A);
  static const surface   = Color(0xFF2C1A10);
  static const card      = Color(0xFF3A2318);
  static const inner     = Color(0xFF4A2E1C);
  static const text      = Color(0xFFF5EDE4);
  static const sub       = Color(0xFFB08B72);
  static const accent    = Color(0xFFD4A373);
  static const mocha     = Color(0xFFB08B72);
  static const caramel   = Color(0xFFD4A373);
  static const latte     = Color(0xFF4A2E1C);
  static const biscotti  = Color(0xFF8D6E63);
  static const error     = Color(0xFFEF9A9A);
  static const foam      = Color(0xFF3A2318);
  static const roast     = Color(0xFFD4A373);
}

// ── Helper: pick light or dark color ───────────────────────────
Color _c(bool d, Color light, Color dark) => d ? dark : light;
// ───────────────────────────────────────────────────────────────

class AddInventorySheet extends StatefulWidget {
  const AddInventorySheet({super.key});

  @override
  State<AddInventorySheet> createState() => _AddInventorySheetState();
}

class _AddInventorySheetState extends State<AddInventorySheet> {
  final _formKey = GlobalKey<FormState>();
  final _name  = TextEditingController();
  final _price = TextEditingController();
  final _stock = TextEditingController(text: "0");

  String  _section = "Syrups";
  String  _unit    = "pcs";
  File?   _image;
  String? _barcode;
  bool    _saving  = false;

  final _picker = ImagePicker();
  final _fs     = FirestoreService();
  final _api    = ApiService();

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _stock.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final x = await _picker.pickImage(
        source: ImageSource.gallery, imageQuality: 80, maxWidth: 1600);
    if (x != null) setState(() => _image = File(x.path));
  }

  void _removeImage() => setState(() => _image = null);

  Future<void> _scanBarcode() async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScanPage()),
    );
    if (!mounted) return;
    final trimmed = code?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      setState(() => _barcode = trimmed);
    }
  }

  void _clearBarcode() => setState(() => _barcode = null);

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();
    setState(() => _saving = true);

    try {
      String? imageUrl;
      if (_image != null) {
        imageUrl = await _api.uploadProductImage(_image!);
      }

      await _fs.addInventoryItem(
        name:         _name.text.trim(),
        section:      _section,
        price:        double.tryParse(_price.text) ?? 0.0,
        imageUrl:     imageUrl,
        barcode:      _barcode,
        initialStock: int.tryParse(_stock.text) ?? 0,
        unit:         _unit,
        reorderLevel: 0,
      );

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: _Coffee.roast,
            content: Text("Save failed: $e",
                style: const TextStyle(color: _Coffee.cream)),
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Input decoration — now dark-aware ──
  InputDecoration _dec(bool d, {
    required String label,
    String?  hint,
    Widget?  prefixIcon,
    String?  prefixText,
  }) {
    return InputDecoration(
      labelText:   label,
      hintText:    hint,
      prefixIcon:  prefixIcon != null
          ? IconTheme(
          data: IconThemeData(color: _c(d, _Coffee.mocha, _Dark.mocha)),
          child: prefixIcon)
          : null,
      prefixText:  prefixText,
      prefixStyle: TextStyle(
          color: _c(d, _Coffee.mocha, _Dark.mocha), fontWeight: FontWeight.w600),
      hintStyle:   TextStyle(
          color: _c(d, _Coffee.biscotti, _Dark.biscotti).withOpacity(0.6)),
      labelStyle:  TextStyle(color: _c(d, _Coffee.mocha, _Dark.mocha)),
      filled:      true,
      fillColor:   _c(d, _Coffee.foam, _Dark.inner),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide:
        BorderSide(color: _c(d, _Coffee.latte, _Dark.latte), width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide:
        BorderSide(color: _c(d, _Coffee.caramel, _Dark.caramel), width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide:
        BorderSide(color: _c(d, _Coffee.error, _Dark.error), width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide:
        BorderSide(color: _c(d, _Coffee.error, _Dark.error), width: 2),
      ),
      floatingLabelStyle: TextStyle(
        color: _c(d, _Coffee.caramel, _Dark.caramel),
        fontWeight: FontWeight.bold,
      ),
    );
  }

  // ── Card wrapper — now dark-aware ──
  Widget _card(bool d, {required Widget child}) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color:        _c(d, _Coffee.foam, _Dark.card),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
          color: _c(d, _Coffee.latte, _Dark.latte), width: 1.5),
      boxShadow: [
        BoxShadow(
          color:      _c(d, _Coffee.mocha, _Dark.bg).withOpacity(d ? 0.35 : 0.06),
          blurRadius: 8,
          offset:     const Offset(0, 2),
        ),
      ],
    ),
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    final d      = AppSettings.of(context).darkMode;
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    // Resolved colors used throughout build
    final sheetBg    = _c(d, Colors.white,     _Dark.surface);
    final handleCol  = _c(d, _Coffee.latte,    _Dark.inner);
    final divCol     = _c(d, _Coffee.latte,    _Dark.latte);
    final textCol    = _c(d, _Coffee.espresso, _Dark.text);
    final subCol     = _c(d, _Coffee.mocha,    _Dark.sub);
    final mochaCol   = _c(d, _Coffee.mocha,    _Dark.mocha);
    final caramelCol = _c(d, _Coffee.caramel,  _Dark.caramel);
    final latteCol   = _c(d, _Coffee.latte,    _Dark.accent);
    final bisCol     = _c(d, _Coffee.biscotti, _Dark.biscotti);
    final errCol     = _c(d, _Coffee.error,    _Dark.error);
    final roastCol   = _c(d, _Coffee.roast,    _Dark.card);
    final dropCol    = _c(d, _Coffee.foam,     _Dark.card);
    final imgBg      = _c(d, _Coffee.latte.withOpacity(0.4), _Dark.inner);
    final barcodeBox = _c(d, _Coffee.latte.withOpacity(0.35), _Dark.inner);

    return Theme(
      data: Theme.of(context).copyWith(
        scaffoldBackgroundColor: _c(d, _Coffee.cream, _Dark.bg),
        colorScheme: ColorScheme.light(
          primary:   _c(d, _Coffee.caramel, _Dark.caramel),
          secondary: _c(d, _Coffee.mocha,   _Dark.mocha),
          surface:   _c(d, _Coffee.foam,    _Dark.card),
          error:     _c(d, _Coffee.error,   _Dark.error),
        ),
        textTheme: Theme.of(context).textTheme.apply(
          bodyColor:    _c(d, _Coffee.espresso, _Dark.text),
          displayColor: _c(d, _Coffee.espresso, _Dark.text),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            color: sheetBg,
            borderRadius:
            const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Padding(
            padding:
            EdgeInsets.fromLTRB(16, 12, 16, 16 + bottom),
            child: SingleChildScrollView(
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Drag handle ──
                    Center(
                      child: Container(
                        width: 44,
                        height: 5,
                        margin:
                        const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: handleCol,
                          borderRadius:
                          BorderRadius.circular(99),
                        ),
                      ),
                    ),

                    // ── Header ──
                    Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          margin: const EdgeInsets.only(right: 10),
                          decoration: BoxDecoration(
                            color: _c(d, _Coffee.caramel, _Dark.accent),
                            borderRadius:
                            BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.inventory_2_outlined,
                            color: _c(d, _Coffee.espresso, _Dark.text),
                            size: 20,
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                            CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Add Inventory Item",
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: textCol,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              Text(
                                "Stock your supplies",
                                style: TextStyle(
                                  fontSize: 12,
                                  color: subCol.withOpacity(0.7),
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: "Close",
                          onPressed: _saving
                              ? null
                              : () => Navigator.pop(context),
                          icon: Icon(Icons.close, color: mochaCol),
                        ),
                      ],
                    ),

                    const SizedBox(height: 6),
                    Divider(color: divCol, height: 24),

                    // ── Name ──
                    TextFormField(
                      controller: _name,
                      enabled: !_saving,
                      textInputAction: TextInputAction.next,
                      style: TextStyle(
                          color: textCol,
                          fontWeight: FontWeight.w500),
                      decoration: _dec(d,
                        label: "Item Name",
                        hint: "e.g. Chocolate Syrup",
                        prefixIcon: const Icon(
                            Icons.inventory_2_outlined,
                        ),
                      ),
                      validator: (v) {
                        final t = (v ?? "").trim();
                        if (t.isEmpty) return "Name is required";
                        if (t.length < 2)
                          return "Name is too short";
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),

                    // ── Section ──
                    DropdownButtonFormField<String>(
                      value: _section,
                      dropdownColor: dropCol,
                      style: TextStyle(
                          color: textCol,
                          fontWeight: FontWeight.w500),
                      onChanged: _saving
                          ? null
                          : (v) => setState(
                              () => _section = v ?? "Syrups"),
                      decoration: _dec(d,
                        label: "Section",
                        prefixIcon: const Icon(
                            Icons.category_outlined),
                      ),
                      items: const [
                        DropdownMenuItem(
                            value: "Syrups",
                            child: Text("Syrups")),
                        DropdownMenuItem(
                            value: "Powder",
                            child: Text("Powder")),
                        DropdownMenuItem(
                            value: "Milk & Cream",
                            child: Text("Milk & Cream")),
                        DropdownMenuItem(
                            value: "Coffee / Tea Base",
                            child: Text("Coffee / Tea Base")),
                        DropdownMenuItem(
                            value: "Toppings",
                            child: Text("Toppings")),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // ── Unit ──
                    DropdownButtonFormField<String>(
                      value: _unit,
                      dropdownColor: dropCol,
                      style: TextStyle(
                          color: textCol,
                          fontWeight: FontWeight.w500),
                      onChanged: _saving
                          ? null
                          : (v) => setState(
                              () => _unit = v ?? "pcs"),
                      decoration: _dec(d,
                        label: "Unit",
                        prefixIcon:
                        const Icon(Icons.straighten),
                      ),
                      items: const [
                        DropdownMenuItem(
                            value: "pcs", child: Text("pcs")),
                        DropdownMenuItem(
                            value: "cup", child: Text("cup")),
                        DropdownMenuItem(
                            value: "bottle",
                            child: Text("bottle")),
                        DropdownMenuItem(
                            value: "kg", child: Text("kg")),
                        DropdownMenuItem(
                            value: "g", child: Text("g")),
                        DropdownMenuItem(
                            value: "ml", child: Text("ml")),
                        DropdownMenuItem(
                            value: "L", child: Text("L")),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // ── Price + Stock ──
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _price,
                            enabled: !_saving,
                            keyboardType:
                            const TextInputType
                                .numberWithOptions(
                                decimal: true),
                            textInputAction:
                            TextInputAction.next,
                            style: TextStyle(
                                color: textCol,
                                fontWeight: FontWeight.w500),
                            inputFormatters: [
                              FilteringTextInputFormatter
                                  .allow(RegExp(r'[\d.]')),
                            ],
                            decoration: _dec(d,
                              label: "Price",
                              hint: "0.00",
                              prefixText: "₱ ",
                              prefixIcon: const Icon(
                                  Icons.payments_outlined),
                            ),
                            validator: (v) {
                              final t = (v ?? "").trim();
                              final p = double.tryParse(t);
                              if (t.isEmpty)
                                return "Required";
                              if (p == null) return "Invalid";
                              if (p <= 0) return "Must be > 0";
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _stock,
                            enabled: !_saving,
                            keyboardType:
                            TextInputType.number,
                            textInputAction:
                            TextInputAction.done,
                            style: TextStyle(
                                color: textCol,
                                fontWeight: FontWeight.w500),
                            inputFormatters: [
                              FilteringTextInputFormatter
                                  .digitsOnly,
                            ],
                            decoration: _dec(d,
                              label: "Initial Stock",
                              hint: "0",
                              prefixIcon: const Icon(
                                  Icons.numbers_outlined),
                            ),
                            validator: (v) {
                              final t = (v ?? "").trim();
                              final n = int.tryParse(t);
                              if (t.isEmpty)
                                return "Required";
                              if (n == null) return "Invalid";
                              if (n < 0)
                                return "Can't be negative";
                              return null;
                            },
                            onFieldSubmitted: (_) =>
                            _saving ? null : _save(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // ── Image picker ──
                    _card(d,
                      child: InkWell(
                        borderRadius:
                        BorderRadius.circular(12),
                        onTap: _saving ? null : _pickImage,
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius:
                              BorderRadius.circular(10),
                              child: Container(
                                width: 64,
                                height: 64,
                                color: imgBg,
                                child: _image == null
                                    ? Icon(
                                    Icons.add_photo_alternate_outlined,
                                    size: 28,
                                    color: bisCol)
                                    : Image.file(_image!,
                                    fit: BoxFit.cover),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _image == null
                                        ? "Add item photo"
                                        : "Photo selected",
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: textCol,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _image == null
                                        ? "Tap to choose from gallery"
                                        : "Tap to change  •  Optional",
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: subCol.withOpacity(0.6),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (_image != null)
                              IconButton(
                                tooltip: "Remove",
                                onPressed: _saving
                                    ? null
                                    : _removeImage,
                                icon: Icon(
                                    Icons.delete_outline,
                                    color: errCol),
                              )
                            else
                              Icon(Icons.chevron_right,
                                  color: bisCol),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── Barcode ──
                    _card(d,
                      child: Column(
                        crossAxisAlignment:
                        CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Icon(
                                  Icons.qr_code_2_outlined,
                                  color: mochaCol),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  "Barcode",
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: textCol,
                                  ),
                                ),
                              ),
                              if (_barcode != null)
                                IconButton(
                                  tooltip: "Clear",
                                  onPressed: _saving
                                      ? null
                                      : _clearBarcode,
                                  icon: Icon(Icons.close,
                                      color: mochaCol),
                                ),
                              FilledButton.tonalIcon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: caramelCol
                                      .withOpacity(d ? 0.25 : 0.18),
                                  foregroundColor: roastCol,
                                ),
                                onPressed: _saving
                                    ? null
                                    : _scanBarcode,
                                icon: const Icon(
                                    Icons.qr_code_scanner,
                                    size: 18),
                                label: const Text("Scan"),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          if (_barcode == null)
                            Text(
                              "None yet  •  Optional",
                              style: TextStyle(
                                fontSize: 12,
                                color: subCol.withOpacity(0.5),
                              ),
                            )
                          else ...[
                            ClipRRect(
                              borderRadius:
                              BorderRadius.circular(10),
                              child: Container(
                                padding:
                                const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 10),
                                color: barcodeBox,
                                child: BarcodeWidget(
                                  barcode: Barcode.code128(),
                                  data: _barcode!,
                                  drawText: false,
                                  width: double.infinity,
                                  height: 80,
                                  color: _c(d, _Coffee.espresso, _Dark.text),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            SelectableText(
                              _barcode!,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: _c(d, _Coffee.espresso, _Dark.text),
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // ── Save button ──
                    SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _saving ? null : _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: roastCol,
                          foregroundColor: latteCol,
                          disabledBackgroundColor:
                          roastCol.withOpacity(0.45),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius:
                              BorderRadius.circular(14)),
                        ),
                        child: _saving
                            ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor:
                            AlwaysStoppedAnimation(latteCol),
                          ),
                        )
                            : Row(
                          mainAxisAlignment:
                          MainAxisAlignment.center,
                          children: [
                            Icon(Icons.coffee,
                                size: 18,
                                color: caramelCol),
                            const SizedBox(width: 8),
                            const Text(
                              "Save Item",
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    Text(
                      "Scan a barcode and add a photo for faster lookup later.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: subCol.withOpacity(0.55),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}