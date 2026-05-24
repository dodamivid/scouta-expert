// ============================================================
//  Scouta Expert — Frontend
//  Se comunica con el servidor Prolog en http://localhost:9090
// ============================================================

const API_BASE = "http://localhost:9090";

const $sintomas = document.getElementById("sintomas");
const $estadoSintomas = document.getElementById("estado-sintomas");
const $resultado = document.getElementById("resultado");
const $btnDiagnosticar = document.getElementById("btn-diagnosticar");
const $btnLimpiar = document.getElementById("btn-limpiar");

// ------------------------------------------------------------
//  Utilidades
// ------------------------------------------------------------

// "voltaje_bajo" -> "Voltaje bajo"
function formatearSintoma(s) {
  const texto = s.replace(/_/g, " ");
  return texto.charAt(0).toUpperCase() + texto.slice(1);
}

function mostrarMensaje(html, clase) {
  $resultado.innerHTML = `<div class="${clase}">${html}</div>`;
}

function setCargando(cargando) {
  $btnDiagnosticar.disabled = cargando;
  document.querySelectorAll(".btn-caso").forEach((b) => (b.disabled = cargando));
}

// ------------------------------------------------------------
//  1. Cargar síntomas y generar checkboxes automáticamente
// ------------------------------------------------------------

async function cargarSintomas() {
  try {
    const resp = await fetch(`${API_BASE}/sintomas`);
    if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
    const data = await resp.json();
    const sintomas = data.sintomas || [];

    $sintomas.innerHTML = "";

    if (sintomas.length === 0) {
      $estadoSintomas.textContent = "El servidor no devolvió síntomas.";
      return;
    }

    sintomas.forEach((s, i) => {
      const id = `sintoma-${i}`;
      const item = document.createElement("div");
      item.className = "sintoma-item";
      item.innerHTML = `
        <input type="checkbox" id="${id}" value="${s}" />
        <label for="${id}">${formatearSintoma(s)}</label>
      `;
      $sintomas.appendChild(item);
    });

    $estadoSintomas.textContent = `${sintomas.length} síntomas disponibles.`;
  } catch (err) {
    $estadoSintomas.textContent = "";
    mostrarMensaje(
      `No se pudieron cargar los síntomas. ¿Está corriendo el servidor en <code>${API_BASE}</code>?<br/><small>${err.message}</small>`,
      "mensaje-error"
    );
  }
}

// ------------------------------------------------------------
//  Síntomas seleccionados
// ------------------------------------------------------------

function getSintomasSeleccionados() {
  return Array.from(
    document.querySelectorAll("#sintomas input[type='checkbox']:checked")
  ).map((cb) => cb.value);
}

// ------------------------------------------------------------
//  Render del resultado (común para diagnosticar y casos)
// ------------------------------------------------------------

function renderResultado(data) {
  // El servidor regresa status "sin_diagnostico" cuando no hay match
  if (data.status === "sin_diagnostico") {
    const msg =
      data.mensaje ||
      "No se encontró diagnóstico para los síntomas seleccionados.";
    mostrarMensaje(`ℹ️ ${msg}`, "mensaje-info");
    return;
  }

  const resultados = data.resultados || [];
  if (resultados.length === 0) {
    mostrarMensaje(
      "ℹ️ No se encontró diagnóstico para los síntomas seleccionados.",
      "mensaje-info"
    );
    return;
  }

  let html = "";

  if (data.caso !== undefined) {
    html += `<span class="caso-badge">Caso de prueba #${data.caso}</span>`;
  }

  resultados.forEach((r) => {
    const explicacion = Array.isArray(r.explicacion)
      ? r.explicacion
      : [r.explicacion];

    const listaExpl = explicacion
      .filter((l) => l && l.trim() !== "")
      .map((l) => `<li>${l}</li>`)
      .join("");

    html += `
      <article class="diag-card">
        <h3>${formatearSintoma(r.diagnostico)}</h3>
        <div class="bloque">
          <strong>¿Por qué este diagnóstico?</strong>
          <ul>${listaExpl || "<li>Sin explicación disponible.</li>"}</ul>
        </div>
        <div class="bloque">
          <strong>Recomendación</strong>
          <div class="recomendacion">${r.recomendacion || "—"}</div>
        </div>
      </article>
    `;
  });

  $resultado.innerHTML = html;
}

// ------------------------------------------------------------
//  2. Diagnosticar (POST con los síntomas seleccionados)
// ------------------------------------------------------------

async function diagnosticar() {
  const sintomas = getSintomasSeleccionados();

  if (sintomas.length === 0) {
    mostrarMensaje(
      "ℹ️ Selecciona al menos un síntoma antes de diagnosticar.",
      "mensaje-info"
    );
    return;
  }

  setCargando(true);
  mostrarMensaje("⏳ Diagnosticando…", "mensaje-info");

  try {
    const resp = await fetch(`${API_BASE}/diagnosticar`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ sintomas }),
    });
    if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
    const data = await resp.json();
    renderResultado(data);
  } catch (err) {
    mostrarMensaje(
      `No se pudo realizar el diagnóstico. ¿Está corriendo el servidor?<br/><small>${err.message}</small>`,
      "mensaje-error"
    );
  } finally {
    setCargando(false);
  }
}

// ------------------------------------------------------------
//  3. Casos de prueba (GET /caso?n=N)
// ------------------------------------------------------------

async function ejecutarCaso(n) {
  setCargando(true);
  mostrarMensaje(`⏳ Ejecutando caso de prueba #${n}…`, "mensaje-info");

  try {
    const resp = await fetch(`${API_BASE}/caso?n=${encodeURIComponent(n)}`);
    if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
    const data = await resp.json();
    renderResultado(data);
  } catch (err) {
    mostrarMensaje(
      `No se pudo ejecutar el caso #${n}. ¿Está corriendo el servidor?<br/><small>${err.message}</small>`,
      "mensaje-error"
    );
  } finally {
    setCargando(false);
  }
}

// ------------------------------------------------------------
//  4. Limpiar (deselecciona checkboxes y borra el resultado)
// ------------------------------------------------------------

function limpiar() {
  document
    .querySelectorAll("#sintomas input[type='checkbox']")
    .forEach((cb) => (cb.checked = false));

  $resultado.innerHTML =
    '<p class="placeholder">Aún no hay diagnóstico. Selecciona síntomas y presiona <strong>Diagnosticar</strong>, o elige un caso de prueba.</p>';
}

// ------------------------------------------------------------
//  Eventos
// ------------------------------------------------------------

$btnDiagnosticar.addEventListener("click", diagnosticar);
$btnLimpiar.addEventListener("click", limpiar);

document.querySelectorAll(".btn-caso").forEach((btn) => {
  btn.addEventListener("click", () => ejecutarCaso(btn.dataset.caso));
});

// Arranque
cargarSintomas();