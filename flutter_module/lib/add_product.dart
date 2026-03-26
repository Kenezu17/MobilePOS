import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'api_service.dart';
import 'firestore_service.dart';
import 'app_settings.dart';

// ── Coffee palette ──────────────────────────────────────────────
class _Coffee {
  static const espresso   = Color(0xFF1C0F0A);
  static const roast      = Color(0xFF3B1F0E);
  static const mocha      = Color(0xFF6B3A23);
  static const caramel    = Color(0xFFC07941);
  static const latte      = Color(0xFFE8CFA8);
  static const cream      = Color(0xFFF5ECD7);
  static const foam       = Color(0xFFFAF3E6);
  static const biscotti   = Color(0xFFD4A96A);
  static const error      = Color(0xFFB84040);
}

class _Dark {
  static const bg        = Color(0xFF1A0F0A);
  static const surface   = Color(0xFF2C1A10);
  static const card      = Color(0xFF3A2318);
  static const inner     = Color(0xFF4A2E1C);
  static const text      = Color(0xFFF5EDE4);
  static const sub       = Color(0xFFB08B72);
  static const accent    = Color(0xFFD4A373);
  static const error     = Color(0xFFEF9A9A);
}

Color _c(bool d, Color light, Color dark) => d ? dark : light;
// ───────────────────────────────────────────────────────────────

class AddProductSheet extends StatefulWidget {
  const AddProductSheet({super.key});

  @override
  State<AddProductSheet> createState() => _AddProductSheetState();
}

class _AddProductSheetState extends State<AddProductSheet> {
  final _formKey       = GlobalKey<FormState>();
  final _imageFieldKey = GlobalKey<FormFieldState<File?>>();

  final _name  = TextEditingController();
  final _price = TextEditingController();
  String _section = "Coffee";

  File? _image;
  bool  _saving = false;

  final _picker = ImagePicker();
  final _api    = ApiService();
  final _fs     = FirestoreService();

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final x = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 1600,
    );
    if (x == null) return;
    setState(() => _image = File(x.path));
    _imageFieldKey.currentState?.didChange(_image);
  }

  void _removeImage() {
    setState(() => _image = null);
    _imageFieldKey.currentState?.didChange(null);
  }

  Future<void> _save() async {
    final ok = _formKey.currentState?.validate() ?? false;
    if (!ok) return;

    if (_image == null) {
      _imageFieldKey.currentState?.validate();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: _Coffee.roast,
          content: Text("Product photo is required",
              style: TextStyle(color: _Coffee.cream)),
        ),
      );
      return;
    }

    final name     = _name.text.trim();
    final priceStr = _price.text.trim().replaceAll(',', '');
    final price    = double.tryParse(priceStr);

    if (price == null || price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: _Coffee.roast,
          content: Text("Enter a valid price",
              style: TextStyle(color: _Coffee.cream)),
        ),
      );
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _saving = true);

    try {
      // 1. Upload image to local server
      final relativePath = await _api.uploadProductImage(_image!);

      // 2. Save product record to Firestore
      await _fs.addProduct(
        name:      name,
        section:   _section,
        price:     price,
        imageUrl:  relativePath, // Local server path
        barcode:   "",
      );

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: _Coffee.roast,
          content: Text("Save failed: $e",
              style: const TextStyle(color: _Coffee.cream)),
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  InputDecoration _dec(bool d, {
    required String label,
    required IconData icon,
    String? prefixText,
  }) {
    return InputDecoration(
      labelText:   label,
      prefixIcon:  Icon(icon, color: _c(d, _Coffee.mocha, _Dark.accent)),
      prefixText:  prefixText,
      prefixStyle: TextStyle(
          color: _c(d, _Coffee.mocha, _Dark.accent), fontWeight: FontWeight.w600),
      labelStyle: TextStyle(color: _c(d, _Coffee.mocha, _Dark.accent)),
      filled:     true,
      fillColor:  _c(d, _Coffee.foam, _Dark.inner),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide:
        BorderSide(color: _c(d, _Coffee.latte, _Dark.inner), width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide:
        BorderSide(color: _c(d, _Coffee.caramel, _Dark.accent), width: 2),
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
        color: _c(d, _Coffee.caramel, _Dark.accent),
        fontWeight: FontWeight.bold,
      ),
    );
  }

  // Section chip helper
  Widget _sectionChip(bool d, String label, IconData icon) {
    final selected = _section == label;
    return GestureDetector(
      onTap: _saving
          ? null
          : () => setState(() => _section = label),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? _c(d, _Coffee.roast, _Dark.accent)
              : _c(d, _Coffee.latte, _Dark.inner).withOpacity(0.4),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: selected ? _c(d, _Coffee.roast, _Dark.accent) : _c(d, _Coffee.latte, _Dark.inner),
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: selected ? _c(d, _Coffee.latte, _Dark.bg) : _c(d, _Coffee.mocha, _Dark.accent),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? _c(d, _Coffee.latte, _Dark.bg) : _c(d, _Coffee.mocha, _Dark.accent),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = AppSettings.of(context).darkMode;
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Theme(
      data: Theme.of(context).copyWith(
        scaffoldBackgroundColor: _c(d, _Coffee.cream, _Dark.bg),
        colorScheme: ColorScheme.light(
          primary:   _c(d, _Coffee.caramel, _Dark.accent),
          secondary: _c(d, _Coffee.mocha, _Dark.accent),
          surface:   _c(d, _Coffee.foam, _Dark.surface),
          error:     _c(d, _Coffee.error, _Dark.error),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            color: _c(d, Colors.white, _Dark.surface),
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
                          color: _c(d, _Coffee.latte, _Dark.inner),
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
                          child:  Icon(
                            Icons.coffee_outlined,
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
                                "Add Product",
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: _c(d, _Coffee.espresso, _Dark.text),
                                  letterSpacing: -0.3,
                                ),
                              ),
                              Text(
                                "Add to your menu",
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _c(d, _Coffee.mocha, _Dark.sub)
                                      .withOpacity(0.7),
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: _saving
                              ? null
                              : () => Navigator.pop(context),
                          icon: Icon(Icons.close,
                              color: _c(d, _Coffee.mocha, _Dark.sub)),
                        ),
                      ],
                    ),

                    const SizedBox(height: 6),
                    Divider(color: _c(d, _Coffee.latte, _Dark.inner), height: 24),

                    // ── Name ──
                    TextFormField(
                      controller: _name,
                      enabled: !_saving,
                      style: TextStyle(
                          color: _c(d, _Coffee.espresso, _Dark.text),
                          fontWeight: FontWeight.w500),
                      decoration: _dec(d,
                          label: "Product Name",
                          icon: Icons.local_cafe_outlined),
                      validator: (v) =>
                      (v ?? "").trim().isEmpty
                          ? "Name is required"
                          : null,
                    ),
                    const SizedBox(height: 16),

                    // ── Section chips ──
                    Text(
                      "Section",
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _c(d, _Coffee.mocha, _Dark.sub),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _sectionChip(d, "Coffee",  Icons.coffee),
                        _sectionChip(d, "Milktea", Icons.local_drink_outlined),
                        _sectionChip(d, "Snacks",  Icons.bakery_dining_outlined),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ── Price ──
                    TextFormField(
                      controller: _price,
                      enabled: !_saving,
                      keyboardType: const TextInputType
                          .numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'[\d.]')),
                      ],
                      style: TextStyle(
                          color: _c(d, _Coffee.espresso, _Dark.text),
                          fontWeight: FontWeight.w500),
                      decoration: _dec(d,
                        label: "Price",
                        icon: Icons.payments_outlined,
                        prefixText: "₱ ",
                      ),
                      validator: (v) {
                        final val =
                        (v ?? "").trim().replaceAll(',', '');
                        if (val.isEmpty) return "Price is required";
                        final parsed = double.tryParse(val);
                        if (parsed == null)
                          return "Enter a valid number";
                        if (parsed <= 0)
                          return "Price must be greater than 0";
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),

                    // ── Image picker ──
                    FormField<File?>(
                      key: _imageFieldKey,
                      validator: (_) => _image == null
                          ? "Product photo is required"
                          : null,
                      builder: (field) {
                        final hasError = field.errorText != null;
                        return Column(
                          crossAxisAlignment:
                          CrossAxisAlignment.start,
                          children: [
                            InkWell(
                              onTap:
                              _saving ? null : _pickImage,
                              borderRadius:
                              BorderRadius.circular(16),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: _c(d, _Coffee.foam, _Dark.inner),
                                  borderRadius:
                                  BorderRadius.circular(16),
                                  border: Border.all(
                                    color: hasError
                                        ? _c(d, _Coffee.error, _Dark.error)
                                        : _c(d, _Coffee.latte, _Dark.inner),
                                    width: 1.5,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: _c(d, _Coffee.mocha, Colors.black)
                                          .withOpacity(0.06),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    ClipRRect(
                                      borderRadius:
                                      BorderRadius.circular(
                                          10),
                                      child: Container(
                                        width: 64,
                                        height: 64,
                                        color: _c(d, _Coffee.latte, _Dark.bg)
                                            .withOpacity(0.35),
                                        child: _image == null
                                            ? Icon(
                                            Icons.add_photo_alternate_outlined,
                                            size: 28,
                                            color: _c(d, _Coffee.biscotti, _Dark.sub))
                                            : Image.file(
                                            _image!,
                                            fit: BoxFit.cover),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                        CrossAxisAlignment
                                            .start,
                                        children: [
                                          Text(
                                            _image == null
                                                ? "Product photo"
                                                : "Photo selected",
                                            style: TextStyle(
                                              fontWeight:
                                              FontWeight.w700,
                                              color:
                                              _c(d, _Coffee.espresso, _Dark.text),
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            _image == null
                                                ? "Required  •  Tap to choose"
                                                : "Tap to change",
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: hasError
                                                  ? _c(d, _Coffee.error, _Dark.error)
                                                  : _c(d, _Coffee.mocha, _Dark.sub)
                                                  .withOpacity(
                                                  0.55),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (_image != null)
                                      IconButton(
                                        onPressed: _removeImage,
                                        icon: Icon(
                                          Icons.delete_outline,
                                          color: _c(d, _Coffee.error, _Dark.error),
                                        ),
                                      )
                                    else
                                      Icon(Icons.chevron_right,
                                          color: _c(d, _Coffee.biscotti, _Dark.sub)),
                                  ],
                                ),
                              ),
                            ),
                            if (hasError)
                              Padding(
                                padding: const EdgeInsets.only(
                                    left: 14, top: 6),
                                child: Text(
                                  field.errorText!,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: _c(d, _Coffee.error, _Dark.error)),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 18),

                    // ── Save button ──
                    SizedBox(
                      height: 52,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: _c(d, _Coffee.roast, _Dark.accent),
                          foregroundColor: _c(d, _Coffee.latte, _Dark.bg),
                          disabledBackgroundColor:
                          _c(d, _Coffee.roast, _Dark.accent).withOpacity(0.45),
                          shape: RoundedRectangleBorder(
                            borderRadius:
                            BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _c(d, _Coffee.latte, _Dark.bg),
                          ),
                        )
                            : Row(
                          mainAxisAlignment:
                          MainAxisAlignment.center,
                          children: [
                            Icon(Icons.coffee,
                                size: 18,
                                color: _c(d, _Coffee.caramel, _Dark.bg)),
                            const SizedBox(width: 8),
                            const Text(
                              "Save Product",
                              style: TextStyle(
                                fontSize: 16,
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
                      "Add a photo to make the product easier to recognize.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 12,
                          color: _c(d, _Coffee.mocha, _Dark.sub).withOpacity(0.55)),
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
