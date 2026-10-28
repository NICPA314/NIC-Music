import { LyricPlayer } from '@applemusic-like-lyrics/core';
import { parseLrc } from '@applemusic-like-lyrics/lyric';
import { handleTTMLParsing } from './ttml-parser';
import '@applemusic-like-lyrics/core/style.css';
import './style.css';
const player = new LyricPlayer();
document.body.appendChild(player.getElement());
let time = 0, playing = false, stamp = performance.now(), last = stamp;
const send = (payload: object) => (window as any).webkit?.messageHandlers?.lyrics?.postMessage(payload);
(window as any).setPlayback = (milliseconds: number, active: boolean) => {time=milliseconds;playing=active;stamp=performance.now();};
(window as any).setLyrics = (text: string, kind: string) => {
  try {
    const lines = kind === 'ttml' ? handleTTMLParsing(text, 'zh-CN').lines : parseLrc(text);
    player.setLyricLines(lines);
    send({event:'loaded',count:lines.length});
  } catch { send({event:'error',message:'歌词文件无法读取'}); }
};
function frame(now: number) {player.setCurrentTime(time+(playing?now-stamp:0));player.update(Math.min(now-last,50));last=now;requestAnimationFrame(frame);}
requestAnimationFrame(frame);
send({event:'ready'});
