import 'package:flutter/material.dart';

import '../utils/supabase_storage.dart';

class StockImageThumbnail extends StatefulWidget {
  const StockImageThumbnail({
    super.key,
    required this.imagePath,
    this.size = 40,
  });

  final String? imagePath;
  final double size;

  @override
  State<StockImageThumbnail> createState() => _StockImageThumbnailState();
}

class _StockImageThumbnailState extends State<StockImageThumbnail> {
  String? _url;
  bool _attemptedSignedUrl = false;
  bool _loadingSignedUrl = false;

  @override
  void initState() {
    super.initState();
    _reset();
  }

  @override
  void didUpdateWidget(covariant StockImageThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imagePath != widget.imagePath) {
      _reset();
    }
  }

  void _reset() {
    _attemptedSignedUrl = false;
    _loadingSignedUrl = false;
    _url = mapStockImagePathToPublicUrl(widget.imagePath);
  }

  String? get _cleanPath {
    final raw = widget.imagePath?.trim();
    if (raw == null || raw.isEmpty) return null;
    return raw;
  }

  String get _heroTag => 'stock-image:${_cleanPath ?? ""}';

  Future<void> _trySignedUrl() async {
    if (_attemptedSignedUrl || _loadingSignedUrl) return;
    _attemptedSignedUrl = true;

    _loadingSignedUrl = true;

    final signed = await createStockImageSignedUrl(widget.imagePath);

    if (!mounted) return;

    setState(() {
      _loadingSignedUrl = false;
      if (signed != null && signed.trim().isNotEmpty) {
        _url = signed;
      }
    });
  }

  void _openViewer() {
    final path = _cleanPath;
    final url = _url;
    if (path == null || url == null) return;

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StockImageViewerPage(
          imagePath: path,
          initialUrl: url,
          heroTag: _heroTag,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final url = _url;

    if (url == null) {
      return CircleAvatar(
        radius: widget.size / 2,
        child: const Icon(Icons.image_not_supported),
      );
    }

    final placeholder = SizedBox(
      width: widget.size,
      height: widget.size,
      child: const Center(
        child: Icon(Icons.image_not_supported),
      ),
    );

    final image = Image.network(
      url,
      width: widget.size,
      height: widget.size,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        if (!_attemptedSignedUrl) {
          Future<void>.microtask(_trySignedUrl);
          return placeholder;
        }
        return placeholder;
      },
    );

    return GestureDetector(
      onTap: _openViewer,
      child: Hero(
        tag: _heroTag,
        child: CircleAvatar(
          radius: widget.size / 2,
          child: ClipOval(child: image),
        ),
      ),
    );
  }
}

class StockImageViewerPage extends StatefulWidget {
  const StockImageViewerPage({
    super.key,
    required this.imagePath,
    required this.initialUrl,
    required this.heroTag,
  });

  final String imagePath;
  final String initialUrl;
  final String heroTag;

  @override
  State<StockImageViewerPage> createState() => _StockImageViewerPageState();
}

class _StockImageViewerPageState extends State<StockImageViewerPage> {
  late String _url;
  bool _attemptedSignedUrl = false;
  bool _loadingSignedUrl = false;

  @override
  void initState() {
    super.initState();
    _url = widget.initialUrl;
  }

  Future<void> _trySignedUrl() async {
    if (_attemptedSignedUrl || _loadingSignedUrl) return;
    _attemptedSignedUrl = true;

    _loadingSignedUrl = true;

    final signed = await createStockImageSignedUrl(widget.imagePath);

    if (!mounted) return;

    setState(() {
      _loadingSignedUrl = false;
      if (signed != null && signed.trim().isNotEmpty) {
        _url = signed;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final image = Image.network(
      _url,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) {
        if (!_attemptedSignedUrl) {
          Future<void>.microtask(_trySignedUrl);
        }

        return const Center(
          child: Icon(Icons.image_not_supported, size: 48),
        );
      },
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Ürün Fotoğrafı')),
      body: Center(
        child: InteractiveViewer(
          child: Hero(
            tag: widget.heroTag,
            child: image,
          ),
        ),
      ),
    );
  }
}
