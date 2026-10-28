import { LyricPlayer, BackgroundRender, MeshGradientRenderer, type LyricLine } from '@applemusic-like-lyrics/core';
import { parseLrc } from '@applemusic-like-lyrics/lyric';
import { handleTTMLParsing } from './ttml-parser';
import '@applemusic-like-lyrics/core/style.css';
import './style.css';
const player = new LyricPlayer();
player.pause();
if (matchMedia('(prefers-reduced-motion: reduce)').matches) { player.setEnableSpring(false); player.setEnableScale(false); }
document.body.appendChild(player.getElement());
let time = 0, playing = false, stamp = performance.now(), last = stamp;
let original: LyricLine[] = [], translation = true, pronunciation = true;
const send = (payload: object) => (window as any).webkit?.messageHandlers?.lyrics?.postMessage(payload);
let ambient: BackgroundRender<MeshGradientRenderer> | undefined;
let ambientOnly = false, ambientActive = false, ambientReduced = false, ambientEnergy = 0;
let ambientMoving: boolean | undefined;
const updateAmbient = () => {
  if (!ambient) return;
  const moving = ambientActive && !ambientReduced && !document.hidden;
  if (moving !== ambientMoving) {
    ambient.setStaticMode(!moving);
    if (moving) ambient.resume(); else ambient.pause();
    ambientMoving = moving;
  }
  ambient.setFlowSpeed(0.6 + ambientEnergy * 1.8);
  // Native AVAudioPlayer supplies real broadband level, not a synthetic beat.
  // Do not present it as the renderer's 50–120 Hz low-frequency measurement.
  ambient.getElement().style.transform = `scale(${1.06 + (moving ? ambientEnergy * 0.035 : 0)})`;
};
(window as any).setAmbientArtwork = async (artwork: string) => {
  ambientOnly = true;
  document.body.dataset.mode = 'ambient';
  if (!ambient) {
    ambient = BackgroundRender.new(MeshGradientRenderer);
    ambient.setRenderScale(0.5); ambient.setFPS(30);
    ambient.getElement().className = 'nic-ambient-background';
    document.body.prepend(ambient.getElement());
  }
  if (!artwork) {
    const fallback = document.createElement('canvas'); fallback.width = fallback.height = 16;
    const context = fallback.getContext('2d')!;
    const gradient = context.createLinearGradient(0, 0, 16, 16);
    gradient.addColorStop(0, '#e64468'); gradient.addColorStop(1, '#654082');
    context.fillStyle = gradient; context.fillRect(0, 0, 16, 16); artwork = fallback.toDataURL();
  }
  await ambient.setAlbum(artwork, false);
  updateAmbient(); send({ event: 'backgroundReady' });
};
(window as any).setAmbientPlayback = (active: boolean, energy: number, reduced: boolean) => {
  ambientActive = active;
  ambientReduced = reduced || matchMedia('(prefers-reduced-motion: reduce)').matches;
  ambientEnergy = Number.isFinite(energy) ? Math.max(0, Math.min(1, energy)) : 0;
  updateAmbient();
};
document.addEventListener('visibilitychange', updateAmbient);
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
  if (playing !== active) { if (active) player.resume(); else player.pause(); }
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
let frameID = 0;
function frame(now: number) {if (!ambientOnly) { player.setCurrentTime(time+(playing?now-stamp:0));player.update(Math.min(now-last,50)); } last=now;frameID=requestAnimationFrame(frame);}
frameID=requestAnimationFrame(frame);
window.addEventListener('pagehide', () => { cancelAnimationFrame(frameID); ambient?.dispose(); player.dispose(); });
send({event:'ready'});
