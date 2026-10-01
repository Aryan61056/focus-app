/* Board behaviour: theme, tabs, veil slider, transparency and motion switches. Not product code. */
(function () {
  var root = document.documentElement;
  function setTheme(v) {
    if (v === "system") root.removeAttribute("data-theme"); else root.setAttribute("data-theme", v);
    document.querySelectorAll("[data-theme-btn]").forEach(function (b) { b.setAttribute("aria-pressed", String(b.dataset.themeBtn === v)); });
    try { localStorage.setItem("board-theme", v); } catch (e) {}
  }
  document.querySelectorAll("[data-theme-btn]").forEach(function (b) { b.addEventListener("click", function () { setTheme(b.dataset.themeBtn); }); });
  var saved = "system";
  try { saved = localStorage.getItem("board-theme") || "system"; } catch (e) {}
  var fromHash = location.hash.replace("#", "");
  setTheme(fromHash === "light" || fromHash === "dark" ? fromHash : saved);

  var tabs = document.querySelectorAll("[role=tab]");
  tabs.forEach(function (t) {
    t.addEventListener("click", function () {
      tabs.forEach(function (x) {
        var on = x === t;
        x.setAttribute("aria-selected", String(on));
        document.getElementById(x.getAttribute("aria-controls")).hidden = !on;
      });
    });
  });

  var opaque = document.getElementById("opaque");
  if (opaque) opaque.addEventListener("change", function () { document.body.classList.toggle("opaque", opaque.checked); });
  var still = document.getElementById("still");
  if (still) still.addEventListener("change", function () { document.body.classList.toggle("still", still.checked); });

  document.querySelectorAll("[data-veil]").forEach(function (s) {
    var target = document.querySelector(s.dataset.veil);
    var out = s.parentElement.querySelector("output");
    function update() { target.style.setProperty("--veil", s.value / 100); if (out) out.textContent = s.value + "%"; }
    s.addEventListener("input", update); update();
  });
})();
