// ============================================================
//  Scouta Expert — Frontend JavaScript
//
//  Autor     : Carlos Alvarado (Integrante 2)
//  Proyecto  : Sistema Experto de Diagnóstico — Robot Scouta
//  Materia   : Programación Lógica y Funcional
//  Equipo    : NexCode Solutions
//
//  Descripción general:
//    Este módulo maneja toda la interacción del usuario en la
//    interfaz web. Se comunica con el servidor SWI-Prolog a
//    través de fetch/JSON para:
//      1. Cargar la lista de síntomas disponibles (GET /sintomas)
//      2. Enviar síntomas seleccionados y obtener diagnósticos
//         (POST /diagnosticar)
//      3. Ejecutar casos de prueba predefinidos (GET /caso?n=N)
//
//  Arquitectura:
//    [Usuario] → [Checkboxes HTML] → [fetch API] → [Servidor Prolog 9090]
//                                                         ↓
//    [Resultado HTML] ←── [renderResultado()] ←── [JSON response]
//
//  Dependencias:
//    - index.html  : estructura del DOM
//    - style.css   : estilos visuales
//    - servidor.pl : backend Prolog en puerto 9090
// ============================================================

/** URL base del servidor Prolog. Debe coincidir con el puerto en servidor.pl */
const API_BASE = "http://localhost:9090";

// ------------------------------------------------------------
//  Referencias al DOM
//  Se obtienen una sola vez al cargar el script para evitar
//  múltiples consultas al DOM en cada interacción.
// ------------------------------------------------------------
const $sintomas         = document.getElementById("sintomas");
const $estadoSintomas   = document.getElementById("estado-sintomas");
const $resultado        = document.getElementById("resultado");
const $btnDiagnosticar  = document.getElementById("btn-diagnosticar");
const $btnLimpiar       = document.getElementById("btn-limpiar");

// ------------------------------------------------------------
//  UTILIDADES
// ------------------------------------------------------------

/**
 * Convierte el nombre interno de un síntoma a texto legible.
 * Ejemplo: "voltaje_bajo" → "Voltaje bajo"
 *
 * @param {string} s - Nombre del síntoma en formato snake_case
 * @returns {string} Texto con primera letra mayúscula y espacios
 */
function formatearSintoma(s) {
  const texto = s.replace(/_/g, " ");
  return texto.charAt(0).toUpperCase() + texto.slice(1);
}

/**
 * Muestra un mensaje en el panel de resultado.
 * Reemplaza cualquier contenido previo en #resultado.
 *
 * @param {string} html  - Contenido HTML del mensaje
 * @param {string} clase - Clase CSS ("mensaje-info" | "mensaje-error")
 */
function mostrarMensaje(html, clase) {
  $resultado.innerHTML = `<div class="${clase}">${html}</div>`;
}

/**
 * Activa o desactiva el estado de carga de la interfaz.
 * Deshabilita el botón de diagnóstico y los botones de casos
 * mientras se espera la respuesta del servidor.
 *
 * @param {boolean} cargando - true para deshabilitar, false para habilitar
 */
function setCargando(cargando) {
  $btnDiagnosticar.disabled = cargando;
  document.querySelectorAll(".btn-caso").forEach((b) => (b.disabled = cargando));
}

// ------------------------------------------------------------
//  1. CARGA DE SÍNTOMAS
//  Solicita al servidor la lista de síntomas disponibles y
//  genera dinámicamente los checkboxes en el grid #sintomas.
// ------------------------------------------------------------

/**
 * Obtiene los síntomas desde GET /sintomas y renderiza los checkboxes.
 *
 * Flujo:
 *   fetch("/sintomas") → [{ sintomas: ["voltaje_bajo", ...] }]
 *   → forEach → crea <div class="sintoma-item"> con <input> + <label>
 *
 * En caso de error (servidor caído), muestra mensaje en #resultado.
 */
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

    // Genera un checkbox por cada síntoma recibido del servidor
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
//  HELPER: obtener síntomas marcados
// ------------------------------------------------------------

/**
 * Devuelve la lista de valores de los checkboxes marcados en #sintomas.
 *
 * @returns {string[]} Array de nombres de síntomas seleccionados
 *                     Ejemplo: ["voltaje_bajo", "arduino_no_inicia"]
 */
function getSintomasSeleccionados() {
  return Array.from(
    document.querySelectorAll("#sintomas input[type='checkbox']:checked")
  ).map((cb) => cb.value);
}

// ------------------------------------------------------------
//  RENDER DE RESULTADOS
//  Función compartida por diagnosticar() y ejecutarCaso().
//  Convierte la respuesta JSON del servidor en tarjetas HTML.
// ------------------------------------------------------------

/**
 * Renderiza los resultados de diagnóstico en el panel #resultado.
 *
 * Estructura de `data` esperada del servidor:
 * {
 *   status: "ok" | "sin_diagnostico",
 *   caso: number (opcional, solo en /caso),
 *   mensaje: string (opcional, cuando sin_diagnostico),
 *   resultados: [
 *     {
 *       diagnostico: "bateria_descargada",
 *       explicacion: ["Razón 1", "Razón 2"],
 *       recomendacion: "Texto de acción a tomar"
 *     }
 *   ]
 * }
 *
 * Cada resultado se muestra como una tarjeta (.diag-card) con:
 *   - Título: nombre del diagnóstico formateado
 *   - Sección "¿Por qué?": lista de líneas de explicación (por_que/1 de Prolog)
 *   - Sección "Recomendación": acción correctiva sugerida
 *
 * @param {Object} data - Respuesta JSON del servidor Prolog
 */
function renderResultado(data) {
  // Caso sin diagnóstico: el motor de inferencia no encontró coincidencias
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

  // Si es respuesta de un caso de prueba, mostrar badge identificador
  if (data.caso !== undefined) {
    html += `<span class="caso-badge">Caso de prueba #${data.caso}</span>`;
  }

  // Construir una tarjeta por cada diagnóstico devuelto
  resultados.forEach((r) => {
    // La explicación puede llegar como array o como string según el servidor
    const explicacion = Array.isArray(r.explicacion)
      ? r.explicacion
      : [r.explicacion];

    // Filtrar líneas vacías y construir lista HTML
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
//  2. DIAGNOSTICAR (síntomas seleccionados por el usuario)
// ------------------------------------------------------------

/**
 * Envía los síntomas seleccionados al servidor y muestra el diagnóstico.
 *
 * Flujo:
 *   getSintomasSeleccionados()
 *   → POST /diagnosticar  { "sintomas": [...] }
 *   → renderResultado(data)
 *
 * Validación: requiere al menos 1 síntoma seleccionado.
 * Estado de carga: deshabilita botones durante la petición.
 */
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
    // Siempre rehabilitar los botones, incluso si hubo error
    setCargando(false);
  }
}

// ------------------------------------------------------------
//  3. CASOS DE PRUEBA (predefinidos en servidor.pl)
// ------------------------------------------------------------

/**
 * Ejecuta un caso de prueba predefinido en el servidor.
 *
 * Flujo:
 *   GET /caso?n=N
 *   → El servidor carga sintomas_caso(N, Sintomas) en Prolog
 *   → Devuelve diagnósticos para ese caso
 *   → renderResultado(data)
 *
 * Los casos disponibles (1-5) están definidos en servidor.pl:
 *   Caso 1: batería descargada en combate
 *   Caso 2: conflicto I2C en los VL53L0X
 *   Caso 3: TCR5000 nunca detecta el borde
 *   Caso 4: solo gira el motor derecho
 *   Caso 5: robot busca rival pero nunca ataca
 *
 * @param {number|string} n - Número del caso de prueba (1-5)
 */
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
//  4. LIMPIAR
// ------------------------------------------------------------

/**
 * Reinicia la interfaz:
 *   - Desmarca todos los checkboxes de síntomas
 *   - Restaura el mensaje placeholder en el panel de resultado
 */
function limpiar() {
  document
    .querySelectorAll("#sintomas input[type='checkbox']")
    .forEach((cb) => (cb.checked = false));

  $resultado.innerHTML =
    '<p class="placeholder">Aún no hay diagnóstico. Selecciona síntomas y presiona <strong>Diagnosticar</strong>, o elige un caso de prueba.</p>';
}

// ------------------------------------------------------------
//  REGISTRO DE EVENTOS
// ------------------------------------------------------------

/** Botón principal: enviar síntomas al motor de inferencia */
$btnDiagnosticar.addEventListener("click", diagnosticar);

/** Botón secundario: limpiar selección y resultado */
$btnLimpiar.addEventListener("click", limpiar);

/**
 * Botones de casos de prueba: cada botón tiene data-caso="N"
 * El evento lee ese atributo y llama ejecutarCaso(N)
 */
document.querySelectorAll(".btn-caso").forEach((btn) => {
  btn.addEventListener("click", () => ejecutarCaso(btn.dataset.caso));
});

// ------------------------------------------------------------
//  INICIALIZACIÓN
//  Al cargar la página se piden los síntomas al servidor.
//  Si el servidor no está disponible, se muestra un error.
// ------------------------------------------------------------
cargarSintomas();
