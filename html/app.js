// whip_threecard: the panel while seated. Lua sends { type: 'show' | 'hud' | 'bet' | 'hide' } (client/play.lua).
// The server's hud says what's true; the timer counts down here from its endsIn.

const $ = (id) => document.getElementById(id);

// whip's scale: its 2560 x 1440 design fitted to the window (whip_core html/js/utils.js).
function applyScale() {
    const s = Math.min(window.innerHeight / 1440, window.innerWidth / 2560);
    document.documentElement.style.setProperty('--ui-scale', s);
}
applyScale();
window.addEventListener('resize', applyScale);

const money = (n) => '$' + Math.floor(Number(n) || 0).toLocaleString('en-US');

let hud = {};
let chosen = 0;           // the bet being picked, before it's placed
let endsAt = 0, span = 0; // the countdown

function esc(t) {
    const d = document.createElement('div');
    d.textContent = t == null ? '' : String(t);
    return d.innerHTML;
}

const RANK = { ace: 'A', jack: 'J', queen: 'Q', king: 'K' };
const SUIT = { hrt: ['♥', true], dia: ['♦', true], club: ['♣', false], spd: ['♠', false] };

// 'hrt_queen' -> a little card face. false: its back.
function cardHtml(card) {
    if (!card) return '<div class="tc-card back"></div>';
    const [suit, rank] = String(card).split('_');
    const r = RANK[rank] || String(parseInt(rank, 10));
    const [sym, red] = SUIT[suit] || ['?', false];
    return `<div class="tc-card${red ? ' red' : ''}"><span class="r">${esc(r)}</span><span class="s">${sym}</span></div>`;
}

const betting = (h) => !h.phase || h.phase === 'idle' || h.phase === 'betting';

function title() {
    const h = hud;
    if (h.ask === 'decide') return ['Play or fold?', 'turn'];
    // The last hand's outcome, until a new round's betting opens.
    if (h.result && (h.phase === 'reveal' || h.phase === 'payout' || (h.phase === 'idle' && !h.ante))) {
        const net = Number(h.net) || 0;
        if (h.result === 'won') return [`You won ${money(net)}`, 'won'];
        if (h.result === 'lost') return [`You lost ${money(-net)}`, 'lost'];
        return ['Bets back', ''];
    }
    switch (h.phase) {
        case 'idle':
        case 'betting':  return [!h.ante ? 'Place your Ante' : (!h.plus ? 'Pair Plus?' : 'Waiting for the deal'), ''];
        case 'dealing':  return [h.ante ? 'Dealing' : 'Sitting out', ''];
        case 'deciding': return [h.ante ? (h.folded ? 'Folded' : (h.play ? 'Playing' : 'Waiting for the table')) : 'Sitting out', ''];
        case 'reveal':   return ["The dealer's hand", ''];
        case 'payout':   return ['Paying out', ''];
    }
    return ['Three Card Poker', ''];
}

function render() {
    const h = hud;
    const [text, tone] = title();
    const t = $('title');
    t.textContent = text;
    t.className = 'tc-title ' + tone;

    // The bet being picked: the Ante, then the Pair Plus.
    const picking = betting(h) && !(h.ante && h.plus);
    $('pick-row').classList.toggle('hidden', !picking);
    $('pick-label').textContent = h.ante ? 'Pair Plus' : 'Ante';
    $('pick').textContent = money(chosen);

    // The bets that are down.
    const bets = [];
    if (h.ante) bets.push(['Ante', h.ante, h.folded]);
    if (h.play) bets.push(['Play', h.play, false]);
    if (h.plus) bets.push(['Pair Plus', h.plus, false]);
    $('bets').innerHTML = bets.map(([name, amount, out]) =>
        `<div class="tc-bet${out ? ' out' : ''}"><span class="tc-label">${esc(name)}</span><span class="tc-amount">${money(amount)}</span></div>`
    ).join('');

    // Your hand, and the dealer's once it's turned over.
    const mine = h.cards && h.cards.length === 3;
    $('mine').classList.toggle('hidden', !mine);
    if (mine) {
        $('mine-cards').innerHTML = h.cards.map(cardHtml).join('');
        $('mine-name').textContent = h.hand || '';
    }
    $('dealer').classList.toggle('hidden', !h.dealer);
    if (h.dealer) {
        $('dealer-cards').innerHTML = h.dealer.cards.map(cardHtml).join('');
        const name = $('dealer-name');
        name.innerHTML = esc(h.dealer.hand) + (h.dealer.qualifies ? '' : '<span class="tc-tag">No qualify</span>');
    }
}

function tick() {
    const timer = $('timer');
    const left = endsAt - Date.now();
    if (!endsAt || left <= 0) { timer.classList.add('hidden'); return; }
    timer.classList.remove('hidden');
    $('timer-bar').style.width = Math.max(0, Math.min(100, (left / span) * 100)) + '%';
    timer.classList.toggle('low', left < 5000);
}
setInterval(tick, 250);

window.addEventListener('message', (e) => {
    const m = e.data || {};
    if (m.type === 'show') {
        hud = { phase: 'idle' };
        chosen = m.bet;
        $('label').textContent = m.label;
        $('limits').textContent = `${money(m.min)} – ${money(m.max)}`;
        $('panel').classList.remove('hidden');
        endsAt = 0;
        render();
    } else if (m.type === 'hud') {
        hud = m.hud || {};
        if (m.bet != null) chosen = m.bet;
        if (hud.endsIn > 0) {
            endsAt = Date.now() + hud.endsIn;
            span = Math.max(hud.span || hud.endsIn, 1);
        } else {
            endsAt = 0;
        }
        render();
        tick();
    } else if (m.type === 'bet') {
        chosen = m.bet;
        render();
    } else if (m.type === 'hide') {
        $('panel').classList.add('hidden');
        hud = {};
        endsAt = 0;
    }
});
