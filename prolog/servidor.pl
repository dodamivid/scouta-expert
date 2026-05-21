% ============================================================
%  Servidor HTTP — Sistema Experto Robot Scouta
%  Puerto: 8080
%  Endpoints:
%    GET  /                  -> index.html (frontend)
%    GET  /sintomas          -> lista de sintomas disponibles (JSON)
%    POST /diagnosticar      -> recibe sintomas, devuelve diagnosticos (JSON)
%    GET  /caso/:n           -> ejecuta caso de prueba n (JSON)
% ============================================================

:- use_module(library(http/thread_httpd)).
:- use_module(library(http/http_dispatch)).
:- use_module(library(http/http_json)).
:- use_module(library(http/http_files)).
:- use_module(library(http/http_parameters)).
:- use_module(library(http/json)).

:- consult('scouta_experto_v2.pl').

% ============================================================
%  RUTAS
% ============================================================

:- http_handler(root(.),          handle_index,       []).
:- http_handler(root(sintomas),   handle_sintomas,    []).
:- http_handler(root(diagnosticar), handle_diagnosticar, [method(post)]).
:- http_handler(root(caso),       handle_caso,        []).

% ============================================================
%  CORS — necesario para que el frontend pueda llamar la API
% ============================================================

add_cors(Request) :-
    memberchk(origin(_), Request), !,
    format('Access-Control-Allow-Origin: *~n'),
    format('Access-Control-Allow-Methods: GET, POST, OPTIONS~n'),
    format('Access-Control-Allow-Headers: Content-Type~n').
add_cors(_).

% ============================================================
%  HANDLER: GET / — sirve el index.html del frontend
% ============================================================

handle_index(Request) :-
    http_reply_file('web/index.html', [], Request).

% ============================================================
%  HANDLER: GET /sintomas
%  Devuelve la lista de todos los síntomas disponibles
%  Respuesta: { "sintomas": ["motores_sin_respuesta", ...] }
% ============================================================

handle_sintomas(Request) :-
    add_cors(Request),
    findall(S, hecho(S), Sintomas),
    % Solo los que son síntomas observables (átomos simples)
    include(atom, Sintomas, SintomasAtom),
    maplist(atom_string, SintomasAtom, SintomasStr),
    reply_json_dict(_{sintomas: SintomasStr}).

% ============================================================
%  HANDLER: POST /diagnosticar
%  Body esperado: { "sintomas": ["voltaje_bajo", "arduino_no_inicia"] }
%  Respuesta:
%  {
%    "status": "ok" | "sin_diagnostico",
%    "resultados": [
%      {
%        "diagnostico": "bateria_descargada",
%        "explicacion": ["...", "..."],
%        "recomendacion": "..."
%      }
%    ]
%  }
% ============================================================

handle_diagnosticar(Request) :-
    add_cors(Request),
    http_read_json_dict(Request, Body, []),
    ( get_dict(sintomas, Body, SintomasStr) ->
        maplist(atom_string, Sintomas, SintomasStr)
    ;
        Sintomas = []
    ),
    % Limpiar síntomas previos e insertar los nuevos
    retractall(sintoma(_)),
    maplist([S]>>(assert(sintoma(S))), Sintomas),
    % Recopilar todos los diagnósticos que aplican
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
        reply_json_dict(_{
            status: "sin_diagnostico",
            mensaje: "No se encontro diagnostico para los sintomas ingresados. Verifica que los sintomas sean correctos.",
            resultados: []
        })
    ;
        reply_json_dict(_{status: "ok", resultados: Resultados})
    ).

% ============================================================
%  HANDLER: GET /caso?n=1
%  Ejecuta un caso de prueba predefinido
%  Respuesta: igual que /diagnosticar
% ============================================================

handle_caso(Request) :-
    add_cors(Request),
    http_parameters(Request, [n(NAtom, [atom])]),
    atom_number(NAtom, N),
    sintomas_caso(N, Sintomas),
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
%  CASOS DE PRUEBA — síntomas para cada caso
% ============================================================

sintomas_caso(1, [voltaje_bajo, arduino_no_inicia]).
sintomas_caso(2, [vl53_lectura_erratica, robot_no_avanza_estrategia]).
sintomas_caso(3, [tcr5000_nunca_activo, robot_no_esquiva_borde]).
sintomas_caso(4, [solo_motor_derecho]).
sintomas_caso(5, [robot_gira_sin_parar, robot_no_avanza_estrategia]).

% ============================================================
%  OBTENER EXPLICACIÓN como lista de strings (para JSON)
% ============================================================

obtener_explicacion(D, Lines) :-
    with_output_to(string(S), por_que(D)),
    split_string(S, "\n", " ", LinesRaw),
    exclude([L]>>(L = ""), LinesRaw, Lines).

% ============================================================
%  ARRANCAR / DETENER EL SERVIDOR
% ============================================================

:- dynamic servidor_activo/1.

iniciar_servidor :-
    ( servidor_activo(_) ->
        write('[!] El servidor ya esta corriendo.'), nl
    ;
        Port =9090,
        http_server(http_dispatch, [port(Port)]),
        assert(servidor_activo(Port)),
        format('[OK] Servidor Scouta corriendo en http://localhost:~w~n', [Port]),
        write('[OK] Endpoints disponibles:'), nl,
        write('       GET  http://localhost:9090/sintomas'), nl,
        write('       POST http://localhost:9090/diagnosticar'), nl,
        write('       GET  http://localhost:9090/caso?n=1  (casos 1-5)'), nl,
        write('       GET  http://localhost:9090/          (frontend)'), nl
    ).

detener_servidor :-
    http_stop_server(9090, []),
    retractall(servidor_activo(_)),
    write('[OK] Servidor detenido.'), nl.

% Arranca automáticamente al cargar el archivo
:- iniciar_servidor.

% ============================================================
%  USO
%  $ swipl servidor.pl
%
%  Para probar desde terminal:
%  curl http://localhost:8080/sintomas
%
%  curl -X POST http://localhost:8080/diagnosticar \
%       -H "Content-Type: application/json" \
%       -d '{"sintomas": ["voltaje_bajo", "arduino_no_inicia"]}'
%
%  curl "http://localhost:8080/caso?n=3"
% ============================================================
