import 'package:flutter/material.dart';

import '../data/chat_emoji_data.dart';
import '../data/chat_gif_sticker_data.dart';

enum ChatEmojiTab { emoji, gif, sticker }

class ChatEmojiPanel extends StatefulWidget {
  final TextEditingController textController;
  final ValueChanged<GifItem> onGifSelected;
  final ValueChanged<StickerItem> onStickerSelected;
  final double height;

  const ChatEmojiPanel({
    super.key,
    required this.textController,
    required this.onGifSelected,
    required this.onStickerSelected,
    this.height = 320,
  });

  @override
  State<ChatEmojiPanel> createState() => _ChatEmojiPanelState();
}

class _ChatEmojiPanelState extends State<ChatEmojiPanel> {
  static final List<String> _recents = [];

  ChatEmojiTab _tab = ChatEmojiTab.emoji;
  bool _searching = false;
  final _searchCtrl = TextEditingController();
  final _emojiScroll = ScrollController();
  int _categoryIndex = 0;
  final Map<String, GlobalKey> _sectionKeys = {};

  @override
  void initState() {
    super.initState();
    for (final c in emojiCategories) {
      _sectionKeys[c.id] = GlobalKey();
    }
    _sectionKeys['recents'] = GlobalKey();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _emojiScroll.dispose();
    super.dispose();
  }

  void _insertEmoji(String emoji) {
    final c = widget.textController;
    final text = c.text;
    final sel = c.selection;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    final next = text.replaceRange(start, end, emoji);
    c.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + emoji.length),
    );
    _recents.remove(emoji);
    _recents.insert(0, emoji);
    if (_recents.length > 32) _recents.removeLast();
    if (mounted) setState(() {});
  }

  void _backspace() {
    final c = widget.textController;
    final text = c.text;
    final sel = c.selection;
    if (!sel.isValid) return;
    if (sel.start != sel.end) {
      final next = text.replaceRange(sel.start, sel.end, '');
      c.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: sel.start),
      );
      return;
    }
    if (sel.start <= 0) return;
    final before = text.substring(0, sel.start);
    final after = text.substring(sel.start);
    final trimmed = before.characters.skipLast(1).toString();
    c.value = TextEditingValue(
      text: trimmed + after,
      selection: TextSelection.collapsed(offset: trimmed.length),
    );
  }

  void _jumpToCategory(int index) {
    setState(() => _categoryIndex = index);
    final id = index == 0 ? 'recents' : emojiCategories[index - 1].id;
    final ctx = _sectionKeys[id]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        alignment: 0.0,
      );
    }
  }

  List<String> _filterEmojis(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final out = <String>[];
    final seen = <String>{};
    for (final cat in emojiCategories) {
      for (final e in cat.emojis) {
        if (seen.contains(e)) continue;
        final hints = emojiSearchHints[e] ?? '';
        if (e.contains(q) || hints.contains(q)) {
          seen.add(e);
          out.add(e);
        }
      }
    }
    return out;
  }

  List<GifItem> _filterGifs(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty || q == 'trending') return curatedGifs;
    return curatedGifs
        .where((g) => g.tags.contains(q) || g.title.toLowerCase().contains(q))
        .toList();
  }

  List<StickerItem> _filterStickers(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return curatedStickers;
    return curatedStickers
        .where((s) => s.tags.contains(q) || s.title.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: SizedBox(
        height: widget.height,
        child: Column(
          children: [
            const SizedBox(height: 6),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFD1D7DB),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 4),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(
                      _searching ? Icons.close : Icons.search,
                      color: const Color(0xFF54656F),
                      size: 22,
                    ),
                    onPressed: () {
                      setState(() {
                        _searching = !_searching;
                        if (!_searching) _searchCtrl.clear();
                      });
                    },
                  ),
                  Expanded(child: _searching ? _buildSearchField() : _buildTabSwitcher()),
                  IconButton(
                    icon: const Icon(Icons.backspace_outlined, color: Color(0xFF54656F), size: 22),
                    onPressed: _tab == ChatEmojiTab.emoji ? _backspace : null,
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE9EDEF)),
            Expanded(child: _buildBody()),
            if (_tab == ChatEmojiTab.emoji && !_searching) _buildCategoryBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    final hint = switch (_tab) {
      ChatEmojiTab.emoji => 'Search emoji',
      ChatEmojiTab.gif => 'Search GIF',
      ChatEmojiTab.sticker => 'Search sticker',
    };
    return TextField(
      controller: _searchCtrl,
      autofocus: true,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF8696A0), fontSize: 15),
        border: InputBorder.none,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
      ),
      style: const TextStyle(fontSize: 15, color: Color(0xFF111B21)),
    );
  }

  Widget _buildTabSwitcher() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: const Color(0xFFF0F2F5),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _tabPill(
              selected: _tab == ChatEmojiTab.emoji,
              child: const Icon(Icons.emoji_emotions, size: 18),
              onTap: () => setState(() => _tab = ChatEmojiTab.emoji),
            ),
            _tabPill(
              selected: _tab == ChatEmojiTab.gif,
              child: const Text('GIF', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              onTap: () => setState(() => _tab = ChatEmojiTab.gif),
            ),
            _tabPill(
              selected: _tab == ChatEmojiTab.sticker,
              child: const Icon(Icons.sticky_note_2_outlined, size: 18),
              onTap: () => setState(() => _tab = ChatEmojiTab.sticker),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabPill({required bool selected, required Widget child, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          boxShadow: selected
              ? const [BoxShadow(color: Color(0x14000000), blurRadius: 2, offset: Offset(0, 1))]
              : null,
        ),
        child: IconTheme(
          data: IconThemeData(color: selected ? const Color(0xFF008069) : const Color(0xFF667781)),
          child: DefaultTextStyle(
            style: TextStyle(
              color: selected ? const Color(0xFF008069) : const Color(0xFF667781),
              fontWeight: FontWeight.w700,
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    return switch (_tab) {
      ChatEmojiTab.emoji => _buildEmojiBody(),
      ChatEmojiTab.gif => _buildGifBody(),
      ChatEmojiTab.sticker => _buildStickerBody(),
    };
  }

  Widget _buildEmojiBody() {
    final q = _searchCtrl.text.trim();
    if (_searching && q.isNotEmpty) {
      final hits = _filterEmojis(q);
      if (hits.isEmpty) {
        return const Center(child: Text('No emoji found', style: TextStyle(color: Color(0xFF667781))));
      }
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 8,
          mainAxisSpacing: 2,
          crossAxisSpacing: 2,
        ),
        itemCount: hits.length,
        itemBuilder: (_, i) => _emojiCell(hits[i]),
      );
    }

    return ListView(
      controller: _emojiScroll,
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
      children: [
        if (_recents.isNotEmpty) ...[
          _sectionHeader('Recents', key: _sectionKeys['recents']),
          _emojiGrid(_recents),
          const SizedBox(height: 10),
        ],
        for (final cat in emojiCategories) ...[
          _sectionHeader(cat.title, key: _sectionKeys[cat.id]),
          _emojiGrid(cat.emojis),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _sectionHeader(String title, {Key? key}) {
    return Padding(
      key: key,
      padding: const EdgeInsets.only(bottom: 6, top: 2),
      child: Text(
        title,
        style: const TextStyle(
          color: Color(0xFF667781),
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _emojiGrid(List<String> emojis) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: emojis.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 8,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
      ),
      itemBuilder: (_, i) => _emojiCell(emojis[i]),
    );
  }

  Widget _emojiCell(String emoji) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _insertEmoji(emoji),
      child: Center(
        child: Text(emoji, style: const TextStyle(fontSize: 26)),
      ),
    );
  }

  Widget _buildCategoryBar() {
    final items = <(IconData, String)>[
      (Icons.access_time, 'recents'),
      ...emojiCategories.map((c) => (c.icon, c.id)),
    ];
    return Container(
      height: 44,
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFE9EDEF))),
        color: Colors.white,
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 4),
        itemBuilder: (context, i) {
          final selected = _categoryIndex == i;
          return GestureDetector(
            onTap: () => _jumpToCategory(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? const Color(0xFFE9EDEF) : Colors.transparent,
                shape: BoxShape.circle,
              ),
              child: Icon(
                items[i].$1,
                size: 20,
                color: selected ? const Color(0xFF008069) : const Color(0xFF667781),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildGifBody() {
    final gifs = _filterGifs(_searching ? _searchCtrl.text : 'trending');
    return Column(
      children: [
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            itemCount: gifQuickChips.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final chip = gifQuickChips[i];
              return ActionChip(
                label: Text(chip, style: const TextStyle(fontSize: 12)),
                onPressed: () {
                  setState(() {
                    _searching = true;
                    _searchCtrl.text = chip == 'Trending' ? '' : chip.toLowerCase();
                  });
                },
                backgroundColor: const Color(0xFFF0F2F5),
                side: BorderSide.none,
                visualDensity: VisualDensity.compact,
              );
            },
          ),
        ),
        Expanded(
          child: gifs.isEmpty
              ? const Center(child: Text('No GIFs found', style: TextStyle(color: Color(0xFF667781))))
              : GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 6,
                    crossAxisSpacing: 6,
                    childAspectRatio: 1.15,
                  ),
                  itemCount: gifs.length,
                  itemBuilder: (context, i) {
                    final g = gifs[i];
                    return GestureDetector(
                      onTap: () => widget.onGifSelected(g),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: ColoredBox(
                          color: const Color(0xFFF0F2F5),
                          child: Image.network(
                            g.previewUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Center(
                              child: Icon(Icons.gif_box_outlined, color: Color(0xFF8696A0)),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildStickerBody() {
    final stickers = _filterStickers(_searching ? _searchCtrl.text : '');
    if (stickers.isEmpty) {
      return const Center(child: Text('No stickers found', style: TextStyle(color: Color(0xFF667781))));
    }
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
      ),
      itemCount: stickers.length,
      itemBuilder: (context, i) {
        final s = stickers[i];
        return GestureDetector(
          onTap: () => widget.onStickerSelected(s),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFFF7F8FA),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Image.network(
                s.imageUrl,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Center(
                  child: Text(s.emoji, style: const TextStyle(fontSize: 36)),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
