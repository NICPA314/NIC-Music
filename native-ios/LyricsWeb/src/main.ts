import { LyricPlayer, type LyricLine } from '@applemusic-like-lyrics/core';
import { parseLrc } from '@applemusic-like-lyrics/lyric';
import { handleTTMLParsing } from './ttml-parser';
import '@applemusic-like-lyrics/core/style.css';
import './style.css';
const player = new LyricPlayer();
document.body.appendChild(player.getElement());
let time = 0, playing = false, stamp = performance.now(), last = stamp;
let original: LyricLine[] = [], translation = true, pronunciation = true;
const send = (payload: object) => (window as any).webkit?.messageHandlers?.lyrics?.postMessage(payload);
const currentTime = () => time + (playing ? performance.now() - stamp : 0);
const render = () => {
  player.setLyricLines(original.map(line => ({
    ...line,
    translatedLyric: translation ? line.translatedLyric : '',
    romanLyric: pronunciation ? line.romanLyric : '',
    words: line.words.map(word => ({ ...word, romanWord: pronunciation ? word.romanWord : '', ruby: pronunciation ? word.ruby : undefined })),
  })), currentTime());
  player.setCurrentTime(currentTime(), true);
};
(window as any).setPlayback = (milliseconds: number, active: boolean) => {
  const seek = Math.abs(milliseconds - currentTime()) > 750;
  time = milliseconds; playing = active; stamp = performance.now();
  if (seek) player.setCurrentTime(time, true);
};
(window as any).setLyricOptions = (showTranslation: boolean, showPronunciation: boolean) => {
  if (translation === showTranslation && pronunciation === showPronunciation) return;
  translation = showTranslation; pronunciation = showPronunciation; render();
};
(window as any).setLyrics = (text: string, kind: string) => {
  try {
    original = kind === 'ttml' ? handleTTMLParsing(text, 'zh-CN').lines : parseLrc(text);
    if (!original.length) throw new Error('没有可显示的歌词');
    render();
    send({event:'loaded', count:original.length,
      translation:original.some(line => !!line.translatedLyric.trim()),
      pronunciation:original.some(line => !!line.romanLyric.trim() || line.words.some(word => !!word.romanWord?.trim() || !!word.ruby?.length))});
  } catch { original = []; render(); send({event:'error',message:'歌词文件无法读取，请检查 TTML／LRC 格式和时间标签。'}); }
};
function frame(now: number) {player.setCurrentTime(time+(playing?now-stamp:0));player.update(Math.min(now-last,50));last=now;requestAnimationFrame(frame);}
requestAnimationFrame(frame);
send({event:'ready'});
