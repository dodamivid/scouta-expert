% ============================================================
%  Servidor HTTP — Sistema Experto Robot Scouta
%  Puerto: 9090
%
%  Descripción:
%    Servidor HTTP construido sobre SWI-Prolog (library http).
%    Expone el motor de inferencia de scouta_experto_v2.pl como
%    una API REST que consume el frontend JavaScript.
%
%  Endpoints:
%    GET  /           → sirve web/index.html (frontend)
%    GET  /sintomas   → lista de síntomas disponibles (JSON)
%    POST /diagnosticar → recibe síntomas, devuelve diagnósticos (JSON)
%    GET  /caso?n=N   → ejecuta caso de prueba N y devuelve resultado (JSON)
%
%  Flujo general de una petición POST /diagnosticar:
%    [Browser] → JSON {sintomas:[...]}
%              → handle_diagnosticar/1
%              → retractall + assert (carga síntomas en la BD dinámica)
%              → findall(diagnostico/recomendacion/explicacion)
%              → reply_json_dict (respuesta JSON)
%              → [Browser]
%
%  Uso:
%    $ swipl servidor.pl
%    El servidor arranca automáticamente al cargar el archivo.
%
%  Para probar desde terminal:
%    curl http://localhost:9090/sintomas
%    curl -X POST http://localhost:9090/diagnosticar \
%         -H "Content-Type: application/json" \
%         -d '{"sintomas": ["voltaje_bajo", "arduino_no_inicia"]}'
%    curl "http://localhost:9090/caso?n=3"
% ============================================================

:- use_module(library(http/thread_httpd)).   % Servidor HTTP multihilo
:- use_module(library(http/http_dispatch)).  % Enrutamiento de peticiones
:- use_module(library(http/http_json)).      % Lectura/escritura de JSON
:- use_module(library(http/http_files)).     % Servir archivos estáticos
:- use_module(library(http/http_parameters)). % Parseo de query params
:- use_module(library(http/json)).           % Tipos JSON nativos de SWI

% Carga el motor de inferencia y la base de conocimiento
:- consult('scouta_experto_v2.pl').

% ============================================================
%  TABLA DE RUTAS
%  http_handler/3 asocia cada path a su predicado manejador.
%  El método HTTP se restringe donde aplica (ej. POST /diagnosticar).
% ============================================================

:- http_handler(root(.),            handle_index,        []).
:- http_handler(root(sintomas),     handle_sintomas,     []).
:- http_handler(root(diagnosticar), handle_diagnosticar, [method(post)]).
:- http_handler(root(caso),         handle_caso,         []).

% ============================================================
%  CORS — Cross-Origin Resource Sharing
%
%  Necesario para que el frontend (servido desde cualquier origen)
%  pueda hacer fetch() a esta API sin ser bloqueado por el navegador.
%  Agrega las cabeceras Access-Control-* a cada respuesta.
%
%  @param Request  Petición HTTP de SWI-Prolog
% ============================================================

add_cors(Request) :-
    memberchk(origin(_), Request), !,   % Solo si la petición trae Origin:
    format('Access-Control-Allow-Origin: *~n'),
    format('Access-Control-Allow-Methods: GET, POST, OPTIONS~n'),
    format('Access-Control-Allow-Headers: Content-Type~n').
add_cors(_).  % Sin Origin: no se agregan cabeceras CORS

% ============================================================
%  HANDLER: GET /
%  Sirve el archivo web/index.html como página principal.
%  La ruta es relativa al directorio donde se ejecuta swipl.
% ============================================================

handle_index(Request) :-
    http_reply_file('web/index.html', [], Request).

% ============================================================
%  HANDLER: GET /sintomas
%
%  Devuelve todos los síntomas observables registrados como
%  hecho/1 en la base de conocimiento.
%
%  Proceso:
%    findall → filtra solo átomos simples (descarta hecho/3)
%    → convierte a strings → responde JSON
%
%  Respuesta exitosa:
%    { "sintomas": ["motores_sin_respuesta", "voltaje_bajo", ...] }
% ============================================================

handle_sintomas(Request) :-
    add_cors(Request),
    findall(S, hecho(S), Sintomas),
    % hecho/1 solo tiene átomos; filtramos por si acaso
    include(atom, Sintomas, SintomasAtom),
    maplist(atom_string, SintomasAtom, SintomasStr),
    reply_json_dict(_{sintomas: SintomasStr}).

% ============================================================
%  HANDLER: POST /diagnosticar
%
%  Recibe síntomas en el body JSON, ejecuta el motor de
%  inferencia y devuelve todos los diagnósticos que aplican.
%
%  Body esperado:
%    { "sintomas": ["voltaje_bajo", "arduino_no_inicia"] }
%
%  Proceso:
%    1. Lee body JSON con http_read_json_dict/3
%    2. Convierte strings → átomos (Prolog trabaja con átomos)
%    3. Limpia la base dinámica y registra los nuevos síntomas
%    4. findall recolecta todos los diagnósticos válidos
%       (diagnostico/1 + recomendacion/2 + obtener_explicacion/2)
%    5. Responde con JSON estructurado
%
%  Respuesta con diagnósticos:
%    {
%      "status": "ok",
%      "resultados": [
%        {
%          "diagnostico": "bateria_descargada",
%          "explicacion": ["Razón 1", "Razón 2"],
%          "recomendacion": "Texto de acción"
%        }
%      ]
%    }
%
%  Respuesta sin diagnóstico:
%    {
%      "status": "sin_diagnostico",
%      "mensaje": "No se encontro diagnostico...",
%      "resultados": []
%    }
% ============================================================

handle_diagnosticar(Request) :-
    add_cors(Request),
    http_read_json_dict(Request, Body, []),
    % Extrae la lista de síntomas del body; usa lista vacía si no viene
    ( get_dict(sintomas, Body, SintomasStr) ->
        maplist(atom_string, Sintomas, SintomasStr)   % string → átomo
    ;
        Sintomas = []
    ),
    % Actualiza la base dinámica con los síntomas recibidos
    retractall(sintoma(_)),
    maplist([S]>>(assert(sintoma(S))), Sintomas),
    % Recolecta todos los diagnósticos aplicables
    findall(
        R,
        ( diagnostico(D),
          recomendacion(D, Rec),
          atom_string(D, DStr),       % átomo → string para JSON
          atom_string(Rec, RecStr),
          obtener_explicacion(D, ExpLines),
          R = _{diagnostico: DStr, explicacion: ExpLines, recomendacion: RecStr}
        ),
        Resultados
    ),
    ( Resultados = [] ->
        reply_json_dict(_{
            status: "sin_diagnostico",
            mensaje: "No se encontro diagnostico para los sintomas ingresados. Verifica que los sintomas sean correctos.",
            resultados: []
        })
    ;
        reply_json_dict(_{status: "ok", resultados: Resultados})
    ).

% ============================================================
%  HANDLER: GET /caso?n=N
%
%  Ejecuta un caso de prueba predefinido sin que el usuario
%  tenga que seleccionar síntomas manualmente.
%
%  Parámetro de query: n (número entero 1-5)
%
%  Proceso:
%    1. Lee el parámetro n con http_parameters/2
%    2. Convierte átomo → número
%    3. Carga los síntomas del caso con sintomas_caso/2
%    4. Ejecuta el mismo pipeline que /diagnosticar
%    5. Incluye el número de caso en la respuesta
%
%  Respuesta exitosa:
%    { "status": "ok", "caso": 3, "resultados": [...] }
% ============================================================

handle_caso(Request) :-
    add_cors(Request),
    http_parameters(Request, [n(NAtom, [atom])]),  % Lee ?n=... como átomo
    atom_number(NAtom, N),                          % Convierte a número
    sintomas_caso(N, Sintomas),                     % Obtiene síntomas del caso
    retractall(sintoma(_)),
    maplist([S]>>(assert(sintoma(S))), Sintomas),
    findall(
        R,
        ( diagnostico(D),
          recomendacion(D, Rec),
          atom_string(D, DStr),
          atom_string(Rec, RecStr),
          obtener_explicacion(D, ExpLines),
          R = _{diagnostico: DStr, explicacion: ExpLines, recomendacion: RecStr}
        ),
        Resultados
    ),
    ( Resultados = [] ->
        reply_json_dict(_{status: "sin_diagnostico", caso: N, resultados: []})
    ;
        reply_json_dict(_{status: "ok", caso: N, resultados: Resultados})
    ).

% ============================================================
%  CASOS DE PRUEBA — sintomas_caso/2
%
%  Define los síntomas de cada caso predefinido.
%  Estos corresponden a los casos/1 definidos en scouta_experto_v2.pl
%  pero en formato de lista para el servidor HTTP.
%
%  @param N        Número de caso (1-5)
%  @param Sintomas Lista de átomos de síntomas para ese caso
% ============================================================

sintomas_caso(1, [voltaje_bajo, arduino_no_inicia]).
    % Caso 1: batería descargada → bateria_descargada
sintomas_caso(2, [vl53_lectura_erratica, robot_no_avanza_estrategia]).
    % Caso 2: conflicto I2C → conflicto_direccion_i2c, umbral_vl53_mal_configurado
sintomas_caso(3, [tcr5000_nunca_activo, robot_no_esquiva_borde]).
    % Caso 3: sensor de borde muerto → tcr5000_desconectado_o_quemado, riesgo_salida_del_dohyo
sintomas_caso(4, [solo_motor_derecho]).
    % Caso 4: motor izquierdo sin respuesta → conexion_motor_izquierdo_suelta
sintomas_caso(5, [robot_gira_sin_parar, robot_no_avanza_estrategia]).
    % Caso 5: lógica de búsqueda infinita → logica_giro_incorrecta

% ============================================================
%  OBTENER EXPLICACIÓN — obtener_explicacion/2
%
%  Captura la salida de por_que/1 (que usa write/nl) y la
%  convierte en una lista de strings para incluir en el JSON.
%
%  Proceso:
%    with_output_to(string(S), por_que(D))
%      → captura todo lo que por_que/1 imprime en S
%    split_string(S, "\n", " ", LinesRaw)
%      → divide por saltos de línea, quitando espacios al inicio
%    exclude([L]>>(L = ""), ...)
%      → filtra líneas vacías
%
%  @param D     Átomo del diagnóstico
%  @param Lines Lista de strings con las líneas de explicación
% ============================================================

obtener_explicacion(D, Lines) :-
    with_output_to(string(S), por_que(D)),          % Captura la salida de texto
    split_string(S, "\n", " ", LinesRaw),            % Divide en líneas
    exclude([L]>>(L = ""), LinesRaw, Lines).         % Elimina líneas vacías

% ============================================================
%  ARRANCAR / DETENER EL SERVIDOR
% ============================================================

% Bandera dinámica para saber si el servidor ya está corriendo.
% Evita lanzar dos instancias en el mismo puerto.
:- dynamic servidor_activo/1.

% iniciar_servidor/0
%   Lanza el servidor HTTP en el puerto 9090.
%   Si ya hay una instancia activa, informa y no hace nada.
iniciar_servidor :-
    ( servidor_activo(_) ->
        write('[!] El servidor ya esta corriendo.'), nl
    ;
        Port = 9090,
        http_server(http_dispatch, [port(Port)]),   % Lanza el servidor
        assert(servidor_activo(Port)),
        format('[OK] Servidor Scouta corriendo en http://localhost:~w~n', [Port]),
        write('[OK] Endpoints disponibles:'), nl,
        write('       GET  http://localhost:9090/sintomas'), nl,
        write('       POST http://localhost:9090/diagnosticar'), nl,
        write('       GET  http://localhost:9090/caso?n=1  (casos 1-5)'), nl,
        write('       GET  http://localhost:9090/          (frontend)'), nl
    ).

% detener_servidor/0
%   Detiene el servidor HTTP y limpia la bandera de estado.
detener_servidor :-
    http_stop_server(9090, []),
    retractall(servidor_activo(_)),
    write('[OK] Servidor detenido.'), nl.

% Directiva de inicialización: arranca el servidor al cargar el archivo.
% Equivalente a llamar iniciar_servidor/0 automáticamente con swipl servidor.pl
:- iniciar_servidor.
