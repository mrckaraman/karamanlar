import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// ignore_for_file: deprecated_member_use

class StockFormPage extends ConsumerStatefulWidget {
  const StockFormPage({super.key, this.stockId});

  final String? stockId;

  @override
  ConsumerState<StockFormPage> createState() => _StockFormPageState();
}

class _StockFormPageState extends ConsumerState<StockFormPage> {
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  final _brandController = TextEditingController();
  final _quantityController = TextEditingController(text: '0');
  final _barcodeController = TextEditingController();
  final _packBarcodeController = TextEditingController();
  final _boxBarcodeController = TextEditingController();
  final _taxRateController = TextEditingController(text: '0');
  final _salePrice1Controller = TextEditingController();
  final _salePrice2Controller = TextEditingController();
  final _salePrice3Controller = TextEditingController();
  final _salePrice4Controller = TextEditingController();
  final _packContainsPieceController = TextEditingController();
  final _caseContainsPieceController = TextEditingController();
  final _groupNameController = TextEditingController();
  final _subgroupNameController = TextEditingController();
  final _subsubgroupNameController = TextEditingController();

  bool _isActive = true;
  bool _loading = false;
  bool _saving = false;
  bool _photoBusy = false;

  String? _imagePath; // DB'deki path
  Uint8List? _pickedImageBytes;
  String? _pickedImageExt;

  @override
  void initState() {
    super.initState();
    _codeController.addListener(_onFormChanged);
    _nameController.addListener(_onFormChanged);
    if (widget.stockId != null) {
      _load();
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _brandController.dispose();
    _quantityController.dispose();
    _barcodeController.dispose();
    _packBarcodeController.dispose();
    _boxBarcodeController.dispose();
    _taxRateController.dispose();
    _salePrice1Controller.dispose();
    _salePrice2Controller.dispose();
    _salePrice3Controller.dispose();
    _salePrice4Controller.dispose();
    _packContainsPieceController.dispose();
    _caseContainsPieceController.dispose();
    _groupNameController.dispose();
    _subgroupNameController.dispose();
    _subsubgroupNameController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final result = await stockRepository.getStockWithUnit(widget.stockId!);
      final stock = result.$1;
      final unit = result.$2;

      _codeController.text = stock.code;
      _nameController.text = stock.name;
      _brandController.text = stock.brand ?? '';
      _taxRateController.text = stock.taxRate.toString();
      _quantityController.text = (stock.quantity ?? 0).toString();
      _barcodeController.text = stock.barcode ?? '';
      _packBarcodeController.text = stock.packBarcode ?? '';
      _boxBarcodeController.text = stock.boxBarcode ?? '';
      _groupNameController.text = stock.groupName ?? '';
      _subgroupNameController.text = stock.subgroupName ?? '';
      _subsubgroupNameController.text = stock.subsubgroupName ?? '';
      _salePrice1Controller.text = stock.salePrice1?.toString() ?? '';
      _salePrice2Controller.text = stock.salePrice2?.toString() ?? '';
      _salePrice3Controller.text = stock.salePrice3?.toString() ?? '';
      _salePrice4Controller.text = stock.salePrice4?.toString() ?? '';
      _isActive = stock.isActive;
      _imagePath = stock.imagePath;

      if (unit != null) {
        _packContainsPieceController.text =
            unit.packContainsPiece?.toString() ?? '';
        _caseContainsPieceController.text =
            unit.caseContainsPiece?.toString() ?? '';
      }

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Stok yüklenemedi: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  double? _parseDouble(String text) {
    if (text.trim().isEmpty) return null;
    return double.tryParse(text.replaceAll(',', '.'));
  }

  int? _parseInt(String text) {
    if (text.trim().isEmpty) return null;
    return int.tryParse(text.trim());
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );

    if (result == null || result.files.isEmpty) return;

    final file = result.files.single;
    if (file.bytes == null) return;

    setState(() {
      _pickedImageBytes = file.bytes;
      _pickedImageExt = file.extension ?? 'jpg';
    });
  }

  Future<void> _changePhoto() async {
    if (_photoBusy) return;
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _photoBusy = true);
    try {
      final stockId = widget.stockId;

      // Yeni stok için: sadece lokalde fotoğrafı seç, kayıt sırasında yüklenecek.
      if (stockId == null) {
        await _pickImage();
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Fotoğraf seçildi. Kaydedince yüklenecek.'),
          ),
        );
        return;
      }

      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.single;
      final bytes = file.bytes;
      if (bytes == null) return;
      final ext = (file.extension ?? 'jpg').toLowerCase();

      final oldPath = _imagePath;

      // Yeni fotoğrafı yükle ve DB'deki image_path'i güncelle.
      final newPath = await stockRepository.uploadStockImage(
        stockId: stockId,
        bytes: bytes,
        fileExt: ext,
      );

      await stockRepository.updateStockImagePath(
        stockId: stockId,
        imagePath: newPath,
      );

      // Eski fotoğraf farklı ise storage'dan temizle (hata sessiz geçilebilir).
      if (oldPath != null &&
          oldPath.isNotEmpty &&
          oldPath != newPath) {
        try {
          await supabaseClient
              .storage
              .from(kStockImagesBucketId)
              .remove([oldPath]);
        } catch (_) {}
      }

      setState(() {
        _imagePath = newPath;
        _pickedImageBytes = bytes;
        _pickedImageExt = ext;
      });

      messenger.showSnackBar(
        const SnackBar(content: Text('Fotoğraf güncellendi')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Fotoğraf güncellenemedi: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _photoBusy = false);
      }
    }
  }

  Future<void> _deletePhoto() async {
    if (_photoBusy) return;
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _photoBusy = true);
    try {
      final currentPath = _imagePath;
      final stockId = widget.stockId;

      // Eğer sadece lokalde seçili fotoğraf varsa, storage'a dokunmadan temizle.
      if (currentPath == null || currentPath.isEmpty) {
        setState(() {
          _pickedImageBytes = null;
          _pickedImageExt = null;
          _imagePath = null;
        });
        messenger.showSnackBar(
          const SnackBar(content: Text('Fotoğraf silindi')),
        );
        return;
      }

      // Storage'dan sil.
      await supabaseClient
          .storage
          .from(kStockImagesBucketId)
          .remove([currentPath]);

      // DB'de image_path'i null'a çek.
      if (stockId != null) {
        await supabaseClient
            .from('stocks')
            .update({'image_path': null})
            .eq('id', stockId);
      }

      setState(() {
        _imagePath = null;
        _pickedImageBytes = null;
        _pickedImageExt = null;
      });

      messenger.showSnackBar(
        const SnackBar(content: Text('Fotoğraf silindi')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Fotoğraf silinemedi: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _photoBusy = false);
      }
    }
  }

  Future<void> _showPhotoOptions() async {
    if (!mounted) return;
    final hasRemote = _imagePath != null && _imagePath!.isNotEmpty;
    final hasLocal = _pickedImageBytes != null;

    await showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_back),
                title: const Text('Fotoğraf Değiştir'),
                onTap: _photoBusy
                    ? null
                    : () {
                        Navigator.of(context).pop();
                        _changePhoto();
                      },
              ),
              ListTile(
                leading: const Icon(Icons.delete),
                title: const Text('Fotoğraf Sil'),
                enabled: !_photoBusy && (hasRemote || hasLocal),
                onTap: (!_photoBusy && (hasRemote || hasLocal))
                    ? () {
                        Navigator.of(context).pop();
                        _deletePhoto();
                      }
                    : null,
              ),
              const Divider(height: 0),
              ListTile(
                leading: const Icon(Icons.close),
                title: const Text('Vazgeç'),
                onTap: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _save() async {
    final code = _codeController.text.trim();
    final name = _nameController.text.trim();

    if (code.isEmpty || name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kod ve ad zorunludur.')),
      );
      return;
    }

    final packText = _packContainsPieceController.text;
    final caseText = _caseContainsPieceController.text;
    final packContainsPiece = _parseInt(packText);
    final caseContainsPiece = _parseInt(caseText);

    final packInvalid =
        packText.trim().isNotEmpty && (packContainsPiece == null || packContainsPiece < 1);
    final caseInvalid =
        caseText.trim().isNotEmpty && (caseContainsPiece == null || caseContainsPiece < 1);

    if (packInvalid || caseInvalid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Paket / Koli adetleri boş bırakılabilir ama girildiyse >= 1 olmalıdır.'),
        ),
      );
      return;
    }

    // Paket barkodu girilmişse paket içi adet zorunludur.
    final hasPackBarcode = _packBarcodeController.text.trim().isNotEmpty;
    if (hasPackBarcode && (packContainsPiece == null || packContainsPiece < 1)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Paket barkodu girilen ürünlerde paket içi adet zorunludur.',
          ),
        ),
      );
      return;
    }

    // Koli barkodu girilmişse koli içi adet zorunludur.
    final hasBoxBarcode = _boxBarcodeController.text.trim().isNotEmpty;
    if (hasBoxBarcode && (caseContainsPiece == null || caseContainsPiece < 1)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Koli barkodu girilen ürünlerde koli içi adet zorunludur.',
          ),
        ),
      );
      return;
    }

    final quantity = _parseDouble(_quantityController.text) ?? 0;
    if (quantity < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Miktar (quantity) 0 veya daha büyük olmalıdır.'),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final stock = Stock(
        id: widget.stockId,
        name: name,
        code: code,
        brand: _brandController.text.trim().isEmpty
            ? null
            : _brandController.text.trim(),
        groupName: _groupNameController.text.trim().isEmpty
          ? null
          : _groupNameController.text.trim(),
        subgroupName: _subgroupNameController.text.trim().isEmpty
          ? null
          : _subgroupNameController.text.trim(),
        subsubgroupName: _subsubgroupNameController.text.trim().isEmpty
          ? null
          : _subsubgroupNameController.text.trim(),
        taxRate: _parseDouble(_taxRateController.text) ?? 0,
        isActive: _isActive,
        imagePath: _imagePath,
        quantity: quantity,
        salePrice1: _parseDouble(_salePrice1Controller.text),
        salePrice2: _parseDouble(_salePrice2Controller.text),
        salePrice3: _parseDouble(_salePrice3Controller.text),
        salePrice4: _parseDouble(_salePrice4Controller.text),
        barcode: _barcodeController.text.trim().isEmpty
          ? null
          : _barcodeController.text.trim(),
        packBarcode: _packBarcodeController.text.trim().isNotEmpty
          ? _packBarcodeController.text.trim()
          : null,
        boxBarcode: _boxBarcodeController.text.trim().isNotEmpty
          ? _boxBarcodeController.text.trim()
          : null,
        specialCode1: null,
        purchasePrice: null,
      );

      // Önce stok kaydedilir
      final saved = await stockRepository.upsertStock(
        stock: stock,
        unit: null,
      );

      // Ardından stok birim adet bilgisi upsert edilir. Boş/0 değerler NULL gönderilir.
      final normalizedPack =
          (packContainsPiece ?? 0) > 0 ? packContainsPiece : null;
      final normalizedCase =
          (caseContainsPiece ?? 0) > 0 ? caseContainsPiece : null;

      await stockRepository.upsertStockUnitValues(
        stockId: saved.id!,
        packContainsPiece: normalizedPack,
        caseContainsPiece: normalizedCase,
      );

      // Yeni stok için seçilen fotoğrafı ilk kayıtta upload et ve path'i güncelle.
      // Düzenleme modunda fotoğraf değişimi _changePhoto() içinde yönetilir.
      if (_pickedImageBytes != null && widget.stockId == null) {
        final path = await stockRepository.uploadStockImage(
          stockId: saved.id!,
          bytes: _pickedImageBytes!,
          fileExt: _pickedImageExt ?? 'jpg',
        );

        await stockRepository.updateStockImagePath(
          stockId: saved.id!,
          imagePath: path,
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Stok kaydedildi.')),
      );
      final router = GoRouter.of(context);
      // Eğer sayfa push ile açıldıysa (ör. /stocks/:id/edit), pop(true) ile dön.
      // Aksi halde (ör. /stocks/new'ye doğrudan go ile gelindiyse) güvenli
      // şekilde liste ekranına yönlendir.
      if (router.canPop()) {
        router.pop(true);
      } else {
        router.go('/stocks/list');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kaydetme hatası: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  void _onFormChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  bool get _isFormValid {
    return _codeController.text.trim().isNotEmpty &&
        _nameController.text.trim().isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.stockId != null;

    String? imageUrl;
    if (_pickedImageBytes == null && _imagePath != null && _imagePath!.isNotEmpty) {
      imageUrl = supabaseClient
          .storage
          .from(kStockImagesBucketId)
          .getPublicUrl(_imagePath!);
    }

    return AppScaffold(
      title: isEdit ? 'Stok Düzenle' : 'Yeni Stok',
      body: _loading
          ? const AppLoadingState()
          : SingleChildScrollView(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 800;

                  final basicInfo = Card(
                    child: Padding(
                      padding: AppSpacing.cardPadding,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _codeController,
                                  decoration: const InputDecoration(
                                    labelText: 'Kod *',
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.s12),
                              Expanded(
                                child: TextField(
                                  controller: _nameController,
                                  decoration: const InputDecoration(
                                    labelText: 'Ad *',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.s8),
                          TextField(
                            controller: _brandController,
                            decoration: const InputDecoration(
                              labelText: 'Marka (opsiyonel)',
                            ),
                          ),
                          const SizedBox(height: AppSpacing.s8),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _quantityController,
                                  decoration: const InputDecoration(
                                    labelText: 'Miktar (adet, >= 0)',
                                  ),
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.s8),
                              Expanded(
                                child: TextField(
                                  controller: _barcodeController,
                                  decoration: const InputDecoration(
                                    labelText: 'Barkod (opsiyonel)',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.s8),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _packBarcodeController,
                                  decoration: const InputDecoration(
                                    labelText: 'Paket barkodu (opsiyonel)',
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.s8),
                              Expanded(
                                child: TextField(
                                  controller: _boxBarcodeController,
                                  decoration: const InputDecoration(
                                    labelText: 'Koli barkodu (opsiyonel)',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.s8),
                          TextField(
                            controller: _taxRateController,
                            decoration: const InputDecoration(
                              labelText: 'KDV Oranı (%)',
                            ),
                            keyboardType:
                                const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );

                  final groupInfo = Card(
                    child: Padding(
                      padding: AppSpacing.cardPadding,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: _groupNameController,
                            decoration: const InputDecoration(
                              labelText: 'Grup adı (opsiyonel)',
                            ),
                          ),
                          const SizedBox(height: AppSpacing.s8),
                          TextField(
                            controller: _subgroupNameController,
                            decoration: const InputDecoration(
                              labelText: 'Ara grup adı (opsiyonel)',
                            ),
                          ),
                          const SizedBox(height: AppSpacing.s8),
                          TextField(
                            controller: _subsubgroupNameController,
                            decoration: const InputDecoration(
                              labelText: 'Alt grup adı (opsiyonel)',
                            ),
                          ),
                        ],
                      ),
                    ),
                  );

                  final prices = Card(
                    child: Padding(
                      padding: AppSpacing.cardPadding,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Satış Fiyatları',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: AppSpacing.s8),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _salePrice1Controller,
                                  decoration: const InputDecoration(
                                    labelText: 'Fiyat-1 (zorunlu değil)',
                                  ),
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.s8),
                              Expanded(
                                child: TextField(
                                  controller: _salePrice2Controller,
                                  decoration: const InputDecoration(
                                    labelText: 'Fiyat-2 (opsiyonel)',
                                  ),
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.s8),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _salePrice3Controller,
                                  decoration: const InputDecoration(
                                    labelText: 'Fiyat-3 (opsiyonel)',
                                  ),
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.s8),
                              Expanded(
                                child: TextField(
                                  controller: _salePrice4Controller,
                                  decoration: const InputDecoration(
                                    labelText: 'Fiyat-4 (opsiyonel)',
                                  ),
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );

                  final conversion = Card(
                    child: Padding(
                      padding: AppSpacing.cardPadding,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Dönüşüm Bilgileri',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: AppSpacing.s8),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _packContainsPieceController,
                                  decoration: const InputDecoration(
                                    labelText: 'Paket içi adet (>=1)',
                                  ),
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                    decimal: false,
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.s8),
                              Expanded(
                                child: TextField(
                                  controller: _caseContainsPieceController,
                                  decoration: const InputDecoration(
                                    labelText: 'Koli içi adet (>=1)',
                                  ),
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                    decimal: false,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );

                  final statusAndImage = Card(
                    child: Padding(
                      padding: AppSpacing.cardPadding,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text('Aktif'),
                              Switch(
                                value: _isActive,
                                onChanged: (value) {
                                  setState(() {
                                    _isActive = value;
                                  });
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.s16),
                          Text(
                            'Fotoğraf',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: AppSpacing.s8),
                          Row(
                            children: [
                              InkWell(
                                onTap: _photoBusy ? null : _showPhotoOptions,
                                child: Container(
                                  width: 80,
                                  height: 80,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: Colors.grey.shade300,
                                    ),
                                  ),
                                  child: _pickedImageBytes != null
                                      ? ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          child: Image.memory(
                                            _pickedImageBytes!,
                                            fit: BoxFit.cover,
                                          ),
                                        )
                                      : (imageUrl != null
                                          ? ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              child: Image.network(
                                                imageUrl,
                                                fit: BoxFit.cover,
                                              ),
                                            )
                                          : const Icon(Icons.image, size: 32)),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.s12),
                              ElevatedButton.icon(
                                onPressed:
                                    _photoBusy ? null : _showPhotoOptions,
                                icon: const Icon(Icons.upload),
                                label: const Text('Fotoğraf Seç'),
                                style: ElevatedButton.styleFrom(
                                  minimumSize: const Size(0, 40),
                                ),
                              ),
                              if (_photoBusy) ...[
                                const SizedBox(width: AppSpacing.s8),
                                const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  );

                  if (isWide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              basicInfo,
                              const SizedBox(height: AppSpacing.s16),
                              prices,
                            ],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.s16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              groupInfo,
                              const SizedBox(height: AppSpacing.s16),
                              conversion,
                              const SizedBox(height: AppSpacing.s16),
                              statusAndImage,
                            ],
                          ),
                        ),
                      ],
                    );
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      basicInfo,
                      const SizedBox(height: AppSpacing.s16),
                      groupInfo,
                      const SizedBox(height: AppSpacing.s16),
                      prices,
                      const SizedBox(height: AppSpacing.s16),
                      conversion,
                      const SizedBox(height: AppSpacing.s16),
                      statusAndImage,
                    ],
                  );
                },
              ),
            ),
      bottom: SafeArea(
        top: false,
        child: Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: AppSpacing.cardPadding,
            child: PrimaryButton(
              label: _saving
                  ? 'Kaydediliyor...'
                  : (isEdit ? 'Güncelle' : 'Kaydet'),
              expand: true,
              onPressed: _saving || !_isFormValid ? null : _save,
            ),
          ),
        ),
      ),
    );
  }
}
