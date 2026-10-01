/* Behaviour for the app window board. Mock interactions and made-up data only; not product code. */
(function () {
  var $ = function (s, r) { return (r || document).querySelector(s); };
  var $$ = function (s, r) { return Array.prototype.slice.call((r || document).querySelectorAll(s)); };

  /* ---- fit the fixed-size window to the page width ---- */
  var fit = $("#fit"), win = $("#win");
  function resize() {
    var w = fit.parentElement.clientWidth;
    var s = Math.min(1, w / 1240);
    fit.style.setProperty("--scale", s);
    win.style.setProperty("--scale", s);
    fit.style.height = Math.round(900 * s + 40) + "px";
    win.style.left = Math.max(0, Math.round((w - 1240 * s) / 2)) + "px";
    win.style.top = "20px";
  }
  window.addEventListener("resize", resize);
  new MutationObserver(resize).observe($("#p-app"), { attributes: true, attributeFilter: ["hidden"] });
  resize();

  var sheet = $("#start-sheet");
  /* ---- navigation ---- */
  function go(view) {
    $$(".a-view").forEach(function (v) { v.hidden = v.dataset.view !== view; });
    $$(".a-nav button[data-go]").forEach(function (b) { if (b.dataset.go === view) b.setAttribute("aria-current", "page"); else b.removeAttribute("aria-current"); });
  }
  $$("[data-go]").forEach(function (b) { b.addEventListener("click", function () { go(b.dataset.go); }); });
  var qv = new URLSearchParams(location.search).get("view"); if (qv) go(qv);
  if (new URLSearchParams(location.search).get("sheet")) { sheet.hidden = false; }

  /* ---- generic selection groups ---- */
  function exclusive(sel, attr) {
    $$(sel, win).forEach(function (b) {
      b.addEventListener("click", function () {
        $$(sel, b.parentElement).forEach(function (x) { x.setAttribute(attr, String(x === b)); });
      });
    });
  }
  exclusive(".chip", "aria-pressed"); exclusive(".a-opt", "aria-pressed"); exclusive(".seg button", "aria-pressed");
  exclusive(".a-set nav button", "aria-current"); exclusive(".a-list button", "aria-current");
  $$(".a-switch").forEach(function (s) { s.addEventListener("click", function () { s.setAttribute("aria-checked", String(s.getAttribute("aria-checked") !== "true")); }); });
  $$(".a-tag button").forEach(function (b) { b.addEventListener("click", function () { b.parentElement.remove(); }); });

  /* ---- start sheet ---- */
  function openSheet() { sheet.hidden = false; $("#close-start").focus(); }
  function closeSheet() { sheet.hidden = true; $("#open-start").focus(); }
  $("#open-start").addEventListener("click", openSheet);
  $("#close-start").addEventListener("click", closeSheet);
  $("#cancel-start").addEventListener("click", closeSheet);
  win.addEventListener("keydown", function (e) { if (e.key === "Escape" && !sheet.hidden) closeSheet(); });

  /* ---- today: timeline ---- */
  var START = 8 * 60, SPAN = 600;
  var seg = [
    ["on", 20, 66], ["off", 66, 67], ["on", 67, 82], ["un", 82, 84], ["on", 84, 90],
    ["on", 125, 150], ["off", 150, 151], ["on", 151, 169],
    ["on", 242, 266]
  ];
  var track = $("#day-track");
  seg.forEach(function (s) {
    var i = document.createElement("i");
    i.className = s[0];
    i.style.left = (s[1] / SPAN * 100) + "%";
    i.style.width = Math.max(0.5, (s[2] - s[1]) / SPAN * 100) + "%";
    track.appendChild(i);
  });
  var now = document.createElement("i"); now.className = "now"; now.style.left = (266 / SPAN * 100) + "%"; now.setAttribute("title", "Now, 12:26"); track.appendChild(now);
  var axis = $("#day-axis");
  [8, 10, 12, 14, 16, 18].forEach(function (h) {
    var s = document.createElement("span"); s.textContent = h + ":00"; s.style.left = ((h * 60 - START) / SPAN * 100) + "%";
    if (h === 8) s.style.transform = "none"; if (h === 18) s.style.transform = "translateX(-100%)";
    axis.appendChild(s);
  });

  /* ---- bar charts ---- */
  function bars(el, daysEl, vals, max, todayIdx, ticks) {
    var days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
    ticks.forEach(function (t, i) {
      var g = document.createElement("span"); g.className = "g"; g.textContent = t + "h"; g.style.top = (i === 0 ? 0 : 50) + "%"; el.appendChild(g);
    });
    vals.forEach(function (v, i) {
      var b = document.createElement("div"); b.className = "a-bar" + (i === todayIdx ? " today" : "");
      b.title = days[i] + ": " + v.toFixed(1) + " hours on task";
      if (v > 0) { var f = document.createElement("i"); f.style.height = (v / max * 100) + "%"; b.appendChild(f); }
      el.appendChild(b);
      var d = document.createElement("span"); d.textContent = days[i]; if (i === todayIdx) d.className = "today"; daysEl.appendChild(d);
    });
  }
  bars($("#week-bars"), $("#week-days"), [2.5, 3.6, 3.0, 2.23, 0, 0, 0], 4, 3, [4, 2]);
  bars($("#avg-bars"), $("#avg-days"), [2.2, 2.6, 2.2, 1.8, 1.0, 0.3, 0.15], 3, -1, [3, 1.5]);

  /* ---- insights heat map, with the morning share worked out from the same data ---- */
  var hrs = [0.2, 0.7, 0.95, 0.9, 0.5, 0.25, 0.35, 0.6, 0.7, 0.55, 0.3, 0.15];
  var dayf = [1, 1, 0.95, 0.9, 0.7, 0.25, 0.15];
  var dn = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
  var heat = $("#heat"), total = 0, morning = 0;
  heat.appendChild(document.createElement("span"));
  dn.forEach(function (d) { var h = document.createElement("span"); h.className = "hd"; h.textContent = d; heat.appendChild(h); });
  hrs.forEach(function (base, hi) {
    var hour = 8 + hi, l = document.createElement("span"); l.textContent = hour + ":00"; heat.appendChild(l);
    dayf.forEach(function (f, di) {
      var v = Math.max(0, Math.min(1, base * f * (0.9 + 0.1 * Math.sin(hi * 3 + di * 5))));
      total += v; if (hour < 12) morning += v;
      var c = document.createElement("span"); c.className = "cell";
      c.style.opacity = v < 0.06 ? 0.07 : (0.15 + 0.85 * v).toFixed(2);
      c.title = dn[di] + " " + hour + ":00, " + Math.round(v * 50) + " focused minutes on average";
      heat.appendChild(c);
    });
  });
  var share = $("#morning-share"); if (share) share.textContent = Math.round(morning / total * 100);

  /* ---- history ---- */
  var S = function (a) { return a; };
  var sessions = [
    { when: "Today, 12:02", proj: "Calc homework", len: "24 min", segs: S([["on", 24]]), slips: 0, nudges: 0, mode: "Open", live: true, sentence: "24 minutes on task so far. No slips yet.", note: "" },
    { when: "Today, 10:05", proj: "Calc homework", len: "44 min", segs: S([["on", 25], ["off", 1], ["on", 18]]), slips: 1, nudges: 0, mode: "Open", sentence: "43 minutes on task. You slipped once and were back in about a minute.", note: "Problems 1 to 3 done. Stuck on 4." },
    { when: "Today, 8:20", proj: "Essay on sleep and memory", len: "1 h 10", segs: S([["on", 46], ["off", 1], ["on", 15], ["un", 2], ["on", 6]]), slips: 1, nudges: 0, mode: "Open", sentence: "67 minutes on task. One slip, and two minutes Focus was not sure about.", note: "" },
    { when: "Wed, 14:30", proj: "Essay on sleep and memory", len: "1 h 35", segs: S([["on", 30], ["off", 3], ["on", 40], ["off", 2], ["on", 20]]), slips: 2, nudges: 1, mode: "Timed", sentence: "90 minutes on task. You slipped twice and one nudge got you back.", note: "Added three citations." },
    { when: "Wed, 9:15", proj: "Lab report on pendulums", len: "1 h 10", segs: S([["on", 36], ["un", 3], ["on", 30], ["off", 1]]), slips: 1, nudges: 0, mode: "Open", sentence: "66 minutes on task. One slip.", note: "" },
    { when: "Tue, 14:10", proj: "Calc homework", len: "1 h 12", segs: S([["on", 30], ["off", 1], ["on", 41]]), slips: 1, nudges: 0, mode: "Open", sentence: "71 minutes on task. One slip, about a minute.", note: "" },
    { when: "Tue, 9:40", proj: "Calc homework", len: "1 h 48", segs: S([["on", 50], ["off", 4], ["on", 48], ["off", 2], ["on", 4]]), slips: 2, nudges: 1, mode: "Timed", sentence: "102 minutes on task. Two slips, and one nudge.", note: "" },
    { when: "Mon, 15:00", proj: "Thesis reading", len: "52 min", segs: S([["on", 28], ["un", 4], ["on", 20]]), slips: 0, nudges: 0, mode: "Open", sentence: "48 minutes on task. Focus was unsure for four minutes while you read a PDF.", note: "" }
  ];
  function mini(segs, cls) {
    var m = document.createElement("div"); m.className = "mini " + (cls || ""); m.setAttribute("aria-hidden", "true");
    segs.forEach(function (s) { var i = document.createElement("i"); i.className = s[0]; i.style.flex = s[1]; m.appendChild(i); });
    return m;
  }
  var rows = $("#hist-rows"), drawer = $("#hist-drawer");
  function select(i) {
    $$(".a-hrow", rows).forEach(function (r, j) { r.setAttribute("aria-selected", String(i === j)); });
    var s = sessions[i];
    drawer.innerHTML = "";
    var h = document.createElement("h3"); h.textContent = s.proj; drawer.appendChild(h);
    var w = document.createElement("div"); w.className = "when"; w.textContent = s.when + " · " + s.len + " · " + s.mode + (s.live ? " · in progress" : ""); drawer.appendChild(w);
    var p = document.createElement("p"); p.className = "a-sentence"; p.textContent = s.sentence; drawer.appendChild(p);
    drawer.appendChild(mini(s.segs, "lg"));
    var lg = document.createElement("div"); lg.className = "a-legend"; lg.innerHTML = '<span><i class="on"></i>On task</span><span><i class="un"></i>Unsure</span><span><i class="off"></i>Off topic</span>'; drawer.appendChild(lg);
    var n = document.createElement("div"); n.className = "note a-field"; n.innerHTML = '<label>Note</label>'; var t = document.createElement("textarea"); t.className = "a-text"; t.rows = 2; t.placeholder = "Add a note for next time"; t.value = s.note; t.setAttribute("aria-label", "Session note"); n.appendChild(t); drawer.appendChild(n);
    var b = document.createElement("button"); b.className = "btn sm plain"; b.type = "button"; b.textContent = "Delete session"; drawer.appendChild(b);
  }
  sessions.forEach(function (s, i) {
    var r = document.createElement("div"); r.className = "a-row a-hrow a-hcols"; r.tabIndex = 0; r.setAttribute("role", "option");
    r.innerHTML = "<span>" + s.when + "</span><b>" + s.proj + "</b><span class=\"a-num a-right\">" + s.len + "</span>";
    var f = document.createElement("div"); f.appendChild(mini(s.segs)); r.appendChild(f);
    var a = document.createElement("span"); a.className = "a-num a-right"; a.textContent = s.slips; r.appendChild(a);
    var c = document.createElement("span"); c.className = "a-num a-right"; c.textContent = s.nudges; r.appendChild(c);
    r.addEventListener("click", function () { select(i); });
    r.addEventListener("keydown", function (e) { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); select(i); } });
    rows.appendChild(r);
  });
  select(1);

  /* ---- review ---- */
  var moments = [
    { when: "Today 10:31", proj: "Calc homework", what: "Browser, a video page, 1 min 40 s", call: "Would have nudged", ring: "r-drift", fine: "Video pages stay off topic for Calc homework." },
    { when: "Today 9:58", proj: "Essay on sleep and memory", what: "Messages, a conversation, 3 min", call: "Close call", ring: "r-unsure", fine: "Messages will not be judged." },
    { when: "Wed 15:12", proj: "Essay on sleep and memory", what: "Browser, a news page, 2 min", call: "Would have nudged", ring: "r-drift", fine: "News pages count for this essay." },
    { when: "Wed 11:03", proj: "Lab report on pendulums", what: "Music app, 6 min", call: "Close call", ring: "r-unsure", fine: "Music counts everywhere." },
    { when: "Tue 16:20", proj: "Calc homework", what: "Browser, a graphing page, 4 min", call: "Would have nudged", ring: "r-drift", fine: "This site counts for Calc homework." }
  ];
  var list = $("#review-list"), left = moments.length, h2 = $("[data-view=review] .a-h2"), badge = $(".a-nav button[data-go=review] .count");
  function setLeft() { h2.textContent = left ? left + " moment" + (left === 1 ? "" : "s") + " to look at" : "All caught up"; badge.textContent = left; if (!left) badge.style.visibility = "hidden"; }
  moments.forEach(function (m) {
    var r = document.createElement("div"); r.className = "a-moment";
    r.innerHTML = '<span class="when">' + m.when + '</span><div><b>' + m.proj + '</b><small>' + m.what + '</small><br><span class="a-call"><span class="ring"><svg><use href="#' + m.ring + '"/></svg></span>' + m.call + '</span></div>';
    var ans = document.createElement("div"); ans.className = "a-ans";
    [["Right call", "Noted. Focus will be a little quicker next time."], ["That was fine", m.fine]].forEach(function (a, i) {
      var b = document.createElement("button"); b.className = "btn sm" + (i ? " plain" : ""); b.type = "button"; b.textContent = a[0];
      b.addEventListener("click", function () {
        ans.className = "res"; ans.textContent = a[1]; r.classList.add("done"); left--; setLeft();
      });
      ans.appendChild(b);
    });
    r.appendChild(ans); list.appendChild(r);
  });
  setLeft();

  /* ---- notch ---- */
  var isl = $("#isl"), stage = $("#isl-stage");
  var states = {
    on:    { mood: "on",    ring: "r-prog",  t: "24:10", s: "On task",       b1: "Pause",  nudge: false },
    drift: { mood: "drift", ring: "r-drift", t: "26:10", s: "Off topic 0:42", b1: "Pause",  nudge: false },
    nudge: { mood: "drift", ring: "r-drift", t: "27:40", s: "",              b1: "Pause",  nudge: true },
    "break": { mood: "break", ring: "r-break", t: "4:12", s: "Back in 4 min", b1: "Resume", nudge: false }
  };
  var cur = "on", pointer = false;
  function render() {
    var st = states[cur];
    isl.dataset.mood = st.mood;
    $$("use", isl).forEach(function (u) { u.setAttribute("href", "#" + st.ring); });
    $("#isl-t").textContent = st.t; $("#isl-t2").textContent = st.t; $("#isl-s").textContent = st.s; $("#isl-b1").textContent = st.b1;
    $(".view-rest b", isl).textContent = cur === "break" ? "Break" : "Calc homework";
    isl.classList.toggle("nudge", st.nudge);
    isl.classList.toggle("open", st.nudge || pointer);
  }
  $$("#isl-states button").forEach(function (b) {
    b.addEventListener("click", function () {
      cur = b.dataset.st; pointer = false;
      $$("#isl-states button").forEach(function (x) { x.setAttribute("aria-pressed", String(x === b)); });
      render();
    });
  });
  isl.addEventListener("mouseenter", function () { pointer = true; render(); });
  isl.addEventListener("mouseleave", function () { pointer = false; render(); });
  isl.addEventListener("focusin", function () { pointer = true; render(); });
  isl.addEventListener("focusout", function (e) { if (!isl.contains(e.relatedTarget)) { pointer = false; render(); } });
  render();
  var q = new URLSearchParams(location.search);
  if (q.get("tab") === "notch") $("#tab-notch").click();
  if (q.get("st")) { var sb = $('#isl-states button[data-st="' + q.get("st") + '"]'); if (sb) sb.click(); }
  if (q.get("open")) { pointer = true; render(); }
})();
