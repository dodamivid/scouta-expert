# 🤖 Scouta Expert System

Sistema Experto para diagnóstico de fallas del robot de sumo autónomo **Scouta**.  
Implementado en **SWI-Prolog** con interfaz web.

**Equipo:** NexCode Solutions  
**Materia:** Programación Lógica y Funcional — ITCH II  

---

## 📁 Estructura del proyecto

```
scouta-expert/
├── prolog/
│   ├── scouta_experto_v2.pl   ← Base de conocimiento (Rey)
│   └── servidor.pl            ← Servidor HTTP (Rey)
├── web/
│   ├── index.html             ← Interfaz de usuario (Integrante 2)
│   ├── style.css              ← Estilos (Integrante 2)
│   └── app.js                 ← Lógica del frontend (Integrante 2)
├── docs/
│   └── documentacion.docx    ← Documentación (Integrante 3)
├── bayesiana/
│   └── red_bayesiana.pl      ← Red bayesiana extra (Integrante 3)
└── README.md
```

---

## ⚙️ Instalación

### 1. Instalar SWI-Prolog

**Windows:**
- Descargar desde https://www.swi-prolog.org/download/stable
- Instalar normalmente, agregar al PATH cuando lo pida

**macOS:**
```bash
brew install swi-prolog
```

**Linux (Ubuntu/Debian):**
```bash
sudo apt install swi-prolog
```

### 2. Clonar el repositorio

```bash
git clone https://github.com/TU_USUARIO/scouta-expert.git
cd scouta-expert
```

### 3. Verificar que los archivos están en su lugar

```
scouta-expert/
├── prolog/scouta_experto_v2.pl
├── prolog/servidor.pl
└── web/index.html
```

---

## 🚀 Cómo correr el sistema

### Opción A — Con interfaz web (modo completo)

```bash
cd prolog
swipl servidor.pl
```

Luego abrir en el navegador: **http://localhost:8080**

El servidor arranca automáticamente al cargar el archivo.  
Para detenerlo desde la consola de SWI-Prolog:
```prolog
?- detener_servidor.
```

### Opción B — Solo consola (modo interactivo)

```bash
cd prolog
swipl scouta_experto_v2.pl
```

```prolog
?- iniciar.
```

El sistema pedirá síntomas uno por uno.

### Opción C — Consulta directa

```prolog
?- consult('scouta_experto_v2.pl').
?- assert(sintoma(voltaje_bajo)), assert(sintoma(arduino_no_inicia)), diagnosticar.
```

---

## 🧪 Casos de prueba

Ejecutar todos los casos desde consola:

```prolog
?- consult('scouta_experto_v2.pl').
?- todos_los_casos.
```

O un caso específico:

```prolog
?- caso(1).   % Batería descargada
?- caso(2).   % Conflicto I2C en VL53L0X
?- caso(3).   % TCR5000 nunca detecta borde
?- caso(4).   % Solo gira motor derecho
?- caso(5).   % Robot busca pero no ataca
```

---

## 🌐 API REST (para el frontend)

### GET /sintomas
Devuelve todos los síntomas disponibles.

```bash
curl http://localhost:8080/sintomas
```

```json
{
  "sintomas": ["motores_sin_respuesta", "voltaje_bajo", "vl53_sin_lectura", ...]
}
```

### POST /diagnosticar
Recibe lista de síntomas, devuelve diagnósticos con explicación.

```bash
curl -X POST http://localhost:8080/diagnosticar \
     -H "Content-Type: application/json" \
     -d '{"sintomas": ["voltaje_bajo", "arduino_no_inicia"]}'
```

```json
{
  "status": "ok",
  "resultados": [
    {
      "diagnostico": "bateria_descargada",
      "explicacion": ["Las 2 baterías 18650 en serie..."],
      "recomendacion": "Recarga o reemplaza las baterías 18650..."
    }
  ]
}
```

### GET /caso?n=N
Ejecuta un caso de prueba predefinido (n = 1 a 5).

```bash
curl "http://localhost:8080/caso?n=3"
```

---

## 📊 Estadísticas del sistema

| Componente | Cantidad |
|---|---|
| Hechos del dominio | 20 |
| Reglas de diagnóstico | 17 |
| Síntomas observables | 15 |
| Diagnósticos posibles | 17 |
| Casos de prueba | 5 |
| Red bayesiana | ✅ (puntos extra) |

---

## 🔀 Flujo de trabajo en GitHub

### Ramas

```
main          ← versión estable, solo merge de ramas aprobadas
├── rey/backend     ← scouta_experto_v2.pl + servidor.pl
├── diego/frontend  ← web/index.html + style.css + app.js
└── ivan/docs       ← README + documentacion + bayesiana
```

### Comandos para cada integrante

**Rey (backend):**
```bash
git checkout -b rey/backend
# trabaja en prolog/
git add prolog/
git commit -m "feat: expandir base de conocimiento a 20 hechos y 17 reglas"
git push origin rey/backend
```

**Integrante 2 (frontend):**
```bash
git checkout -b diego/frontend
# trabaja en web/
git add web/
git commit -m "feat: interfaz web con checkboxes para selección de síntomas"
git push origin diego/frontend
```

**Integrante 3 (docs):**
```bash
git checkout -b ivan/docs
# trabaja en docs/ y bayesiana/
git add docs/ bayesiana/ README.md
git commit -m "docs: agregar documentación y red bayesiana"
git push origin ivan/docs
```

---

## 🤖 Hardware de Scouta

| Componente | Modelo | Función |
|---|---|---|
| Microcontrolador | Arduino Nano | Control central |
| Driver motores | TB6612FNG | PWM + dirección |
| Motores | 2x N20 | Tracción |
| Batería | 2x 18650 serie (7.4V) | Alimentación |
| Sensores distancia | 3x VL53L0X | Detección rival (I2C) |
| Sensores borde | 2x TCR5000 | Detección línea negra |
