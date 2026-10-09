// DOM overlay: clock, objectives, field gauges, stamina, toolbar, prompts.
import { TOOLS } from './tools.js';

const $ = id => document.getElementById(id);

export class Hud {
  constructor() {
    this.el = {
      clock: $('clock'), objective: $('objective'), stats: $('stats'), stamina: $('stamina-fill'),
      inv: $('inv'), toolbar: $('toolbar'), prompt: $('prompt'), log: $('log'), banner: $('banner'),
      rhythmScore: $('rhythm-score'), flash: $('flash'), vignette: $('vignette'),
    };
    this.el.toolbar.innerHTML = TOOLS.map(t => `<div class="slot" data-id="${t.id}"><b>${t.key}</b>${t.name}<small>${t.en}</small></div>`).join('');
    this.cache = {};
  }

  set(key, html) {
    if (this.cache[key] === html) return;
    this.cache[key] = html;
    this.el[key].innerHTML = html;
  }

  tool(id) {
    this.el.toolbar.querySelectorAll('.slot').forEach(s => s.classList.toggle('on', s.dataset.id === id));
  }

  stamina(v) {
    this.el.stamina.style.width = `${v}%`;
    this.el.stamina.classList.toggle('low', v < 25);
  }

  prompt(text) { this.set('prompt', text ? `<kbd>E</kbd> ${text}` : ''); }
  hint(text) { this.set('prompt', text || ''); }
  banner(html) { this.set('banner', html || ''); this.el.banner.hidden = !html; }
  setRhythmScore(t) { this.set('rhythmScore', t); }

  log(text, kind = 'info') {
    const div = document.createElement('div');
    div.className = 'msg ' + kind;
    div.textContent = text;
    this.el.log.appendChild(div);
    while (this.el.log.children.length > 4) this.el.log.firstChild.remove();
    setTimeout(() => div.classList.add('fade'), 7000);
    setTimeout(() => div.remove(), 8500);
  }

  flash(strength) { this.el.flash.style.opacity = strength; }
  vignette(v) { this.el.vignette.style.opacity = v; }
}
