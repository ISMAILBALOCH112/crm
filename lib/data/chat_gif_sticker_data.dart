class GifItem {
  final String id;
  final String previewUrl;
  final String mediaUrl;
  final String tags;
  final String title;
  const GifItem({required this.id, required this.previewUrl, required this.mediaUrl, required this.tags, required this.title});
}

class StickerItem {
  final String id;
  final String imageUrl;
  final String tags;
  final String title;
  final String emoji;
  const StickerItem({required this.id, required this.imageUrl, required this.tags, required this.title, required this.emoji});
}

const List<GifItem> curatedGifs = [
  GifItem(id: '3o7aCTPPm4OHfRLSH6', previewUrl: 'https://media.giphy.com/media/3o7aCTPPm4OHfRLSH6/200.gif', mediaUrl: 'https://media.giphy.com/media/3o7aCTPPm4OHfRLSH6/giphy.mp4', tags: 'excited happy wow dance', title: 'Excited'),
  GifItem(id: 'JIX9t2j0ZTN9S', previewUrl: 'https://media.giphy.com/media/JIX9t2j0ZTN9S/200.gif', mediaUrl: 'https://media.giphy.com/media/JIX9t2j0ZTN9S/giphy.mp4', tags: 'cat funny cute typing', title: 'Cat typing'),
  GifItem(id: 'l0HlvtIPzPdt2usKs', previewUrl: 'https://media.giphy.com/media/l0HlvtIPzPdt2usKs/200.gif', mediaUrl: 'https://media.giphy.com/media/l0HlvtIPzPdt2usKs/giphy.mp4', tags: 'love heart kiss', title: 'Love'),
  GifItem(id: '111ebonMs90YLu', previewUrl: 'https://media.giphy.com/media/111ebonMs90YLu/200.gif', mediaUrl: 'https://media.giphy.com/media/111ebonMs90YLu/giphy.mp4', tags: 'thumbs up yes ok agree', title: 'Thumbs up'),
  GifItem(id: '26u4cqiYI30juCOGY', previewUrl: 'https://media.giphy.com/media/26u4cqiYI30juCOGY/200.gif', mediaUrl: 'https://media.giphy.com/media/26u4cqiYI30juCOGY/giphy.mp4', tags: 'bye wave goodbye', title: 'Bye'),
  GifItem(id: 'xT0xeJpnrWC4XWblEk', previewUrl: 'https://media.giphy.com/media/xT0xeJpnrWC4XWblEk/200.gif', mediaUrl: 'https://media.giphy.com/media/xT0xeJpnrWC4XWblEk/giphy.mp4', tags: 'wow mind blown shocked', title: 'Wow'),
  GifItem(id: '9Y5BbDSkSTiY8', previewUrl: 'https://media.giphy.com/media/9Y5BbDSkSTiY8/200.gif', mediaUrl: 'https://media.giphy.com/media/9Y5BbDSkSTiY8/giphy.mp4', tags: 'sad cry tears', title: 'Sad'),
  GifItem(id: '3oEjI6SIIHBdRxXI40', previewUrl: 'https://media.giphy.com/media/3oEjI6SIIHBdRxXI40/200.gif', mediaUrl: 'https://media.giphy.com/media/3oEjI6SIIHBdRxXI40/giphy.mp4', tags: 'loading waiting think', title: 'Waiting'),
];

const List<String> gifQuickChips = [
  'Trending',
  'Happy',
  'Love',
  'Sad',
  'Funny',
  'Yes',
  'No',
  'Bye',
  'Thanks',
  'OK',
  'Party',
  'Wow',
];

const List<StickerItem> curatedStickers = [
  StickerItem(id: '1f44d', imageUrl: 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f44d.png', tags: 'thumbs up yes ok', title: 'Thumbs up', emoji: '👍'),
  StickerItem(id: '1f44e', imageUrl: 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f44e.png', tags: 'thumbs down no', title: 'Thumbs down', emoji: '👎'),
  StickerItem(id: '1f44b', imageUrl: 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f44b.png', tags: 'wave hello bye hi', title: 'Wave', emoji: '👋'),
  StickerItem(id: '1f64f', imageUrl: 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f64f.png', tags: 'pray thanks please', title: 'Pray', emoji: '🙏'),
  StickerItem(id: '1f4aa', imageUrl: 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f4aa.png', tags: 'strong muscle', title: 'Strong', emoji: '💪'),
  StickerItem(id: '1f389', imageUrl: 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f389.png', tags: 'party celebrate', title: 'Party', emoji: '🎉'),
  StickerItem(id: '1f525', imageUrl: 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f525.png', tags: 'fire lit hot', title: 'Fire', emoji: '🔥'),
  StickerItem(id: '2764', imageUrl: 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/2764.png', tags: 'love heart', title: 'Heart', emoji: '❤️'),
  StickerItem(id: '1f60d', imageUrl: 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f60d.png', tags: 'love heart eyes', title: 'Love', emoji: '😍'),
  StickerItem(id: '1f602', imageUrl: 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f602.png', tags: 'laugh lol joy', title: 'Laugh', emoji: '😂'),
  StickerItem(id: '1f62d', imageUrl: 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f62d.png', tags: 'cry sad', title: 'Cry', emoji: '😭'),
  StickerItem(id: '1f621', imageUrl: 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f621.png', tags: 'angry mad', title: 'Angry', emoji: '😡'),
  StickerItem(id: '1f914', imageUrl: 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f914.png', tags: 'think hmm', title: 'Think', emoji: '🤔'),
  StickerItem(id: '1f44c', imageUrl: 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f44c.png', tags: 'ok okay', title: 'OK', emoji: '👌'),
  StickerItem(id: '1f91d', imageUrl: 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f91d.png', tags: 'handshake deal', title: 'Deal', emoji: '🤝'),
  StickerItem(id: '1f64c', imageUrl: 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f64c.png', tags: 'raise hands hooray', title: 'Hooray', emoji: '🙌'),
  StickerItem(id: '1f918', imageUrl: 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f918.png', tags: 'rock metal', title: 'Rock', emoji: '🤘'),
  StickerItem(id: '1f919', imageUrl: 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f919.png', tags: 'call me', title: 'Call', emoji: '🤙'),
  StickerItem(id: '1f605', imageUrl: 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f605.png', tags: 'sweat laugh nervous', title: 'Nervous', emoji: '😅'),
  StickerItem(id: '1f929', imageUrl: 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f929.png', tags: 'star struck wow', title: 'Star', emoji: '🤩'),
  StickerItem(id: '1f970', imageUrl: 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f970.png', tags: 'love smiling', title: 'Smile love', emoji: '🥰'),
  StickerItem(id: '1f973', imageUrl: 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f973.png', tags: 'party face', title: 'Party face', emoji: '🥳'),
  StickerItem(id: '1f60e', imageUrl: 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f60e.png', tags: 'cool sunglasses', title: 'Cool', emoji: '😎'),
  StickerItem(id: '1f92f', imageUrl: 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f92f.png', tags: 'mind blown', title: 'Mind blown', emoji: '🤯'),
  StickerItem(id: '1f436', imageUrl: 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f436.png', tags: 'dog puppy cute', title: 'Dog', emoji: '🐶'),
  StickerItem(id: '1f431', imageUrl: 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f431.png', tags: 'cat kitten cute', title: 'Cat', emoji: '🐱'),
  StickerItem(id: '1f98b', imageUrl: 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f98b.png', tags: 'butterfly', title: 'Butterfly', emoji: '🦋'),
  StickerItem(id: '1f338', imageUrl: 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f338.png', tags: 'cherry blossom flower', title: 'Blossom', emoji: '🌸'),
  StickerItem(id: '1f33a', imageUrl: 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f33a.png', tags: 'hibiscus flower', title: 'Flower', emoji: '🌺'),
  StickerItem(id: '1f30d', imageUrl: 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f30d.png', tags: 'earth world', title: 'Earth', emoji: '🌍'),
  StickerItem(id: '1f319', imageUrl: 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f319.png', tags: 'moon night', title: 'Moon', emoji: '🌙'),
  StickerItem(id: '2600', imageUrl: 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/2600.png', tags: 'sun sunny', title: 'Sun', emoji: '☀️'),
  StickerItem(id: '1f308', imageUrl: 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f308.png', tags: 'rainbow', title: 'Rainbow', emoji: '🌈'),
  StickerItem(id: '2b50', imageUrl: 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/2b50.png', tags: 'star', title: 'Star', emoji: '⭐'),
  StickerItem(id: '1f381', imageUrl: 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f381.png', tags: 'gift present', title: 'Gift', emoji: '🎁'),
  StickerItem(id: '1f382', imageUrl: 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f382.png', tags: 'birthday cake', title: 'Cake', emoji: '🎂'),
  StickerItem(id: '1f355', imageUrl: 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f355.png', tags: 'pizza food', title: 'Pizza', emoji: '🍕'),
  StickerItem(id: '2615', imageUrl: 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/2615.png', tags: 'coffee tea', title: 'Coffee', emoji: '☕'),
  StickerItem(id: '1f37a', imageUrl: 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f37a.png', tags: 'beer cheers', title: 'Beer', emoji: '🍺'),
  StickerItem(id: '26bd', imageUrl: 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/26bd.png', tags: 'soccer football', title: 'Soccer', emoji: '⚽'),
  StickerItem(id: '1f3c6', imageUrl: 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f3c6.png', tags: 'trophy win', title: 'Trophy', emoji: '🏆'),
  StickerItem(id: '1f680', imageUrl: 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f680.png', tags: 'rocket', title: 'Rocket', emoji: '🚀'),
  StickerItem(id: '1f697', imageUrl: 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f697.png', tags: 'car', title: 'Car', emoji: '🚗'),
  StickerItem(id: '2708', imageUrl: 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/2708.png', tags: 'plane airplane', title: 'Plane', emoji: '✈️'),
  StickerItem(id: '1f3e0', imageUrl: 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f3e0.png', tags: 'home house', title: 'Home', emoji: '🏠'),
  StickerItem(id: '1f4f1', imageUrl: 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f4f1.png', tags: 'phone mobile', title: 'Phone', emoji: '📱'),
  StickerItem(id: '1f4bb', imageUrl: 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f4bb.png', tags: 'laptop computer', title: 'Laptop', emoji: '💻'),
  StickerItem(id: '1f4a1', imageUrl: 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f4a1.png', tags: 'idea bulb', title: 'Idea', emoji: '💡'),
];
