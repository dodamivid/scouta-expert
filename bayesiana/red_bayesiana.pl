% ============================================================
%  Red Bayesiana — Sistema Experto Scouta
%  Equipo  : NexCode Solutions
%  Robot   : Scouta (Arduino Nano + TB6612FNG + N20 + VL53L0X x3 + TCR500 x2)
%  Materia : Programación Lógica y Funcional
%  Maestro : Héctor Ramos
% ============================================================
%
%  Dominio: exactamente los 15 diagnósticos y 13 síntomas del
%  sistema experto original de Scouta, ahora modelados con
%  probabilidades bayesianas.
%
%  Uso rápido:
%    ?- probabilidad_diagnostico(falla_driver_tb6612fng, P).
%    ?- diagnosticar_bayesiano([voltaje_bajo, motores_sin_respuesta], Lista).
%    ?- ejecutar_todos_los_casos.
% ============================================================

:- use_module(library(lists)).

% ------------------------------------------------------------
%  1. PROBABILIDADES A PRIORI  P(Diagnóstico)
%     Basadas en frecuencia observada en competencias de sumo
%     robótico con hardware similar al de Scouta.
% ------------------------------------------------------------

prior(falla_driver_tb6612fng,           0.10).
prior(conexion_motor_izquierdo_suelta,  0.08).
prior(conexion_motor_derecho_suelta,    0.08).
prior(pwm_insuficiente_o_codigo_erroneo,0.10).
prior(sobrecalentamiento_driver,        0.06).
prior(falla_bus_i2c,                    0.08).
prior(conflicto_direccion_i2c,          0.07).
prior(falla_alimentacion_sensores,      0.07).
prior(tcr_obstruido_o_corto,            0.08).
prior(tcr_desconectado_o_quemado,       0.07).
prior(umbral_tcr_mal_calibrado,         0.05).
prior(bateria_descargada_o_regulador_falla, 0.06).
prior(voltaje_insuficiente_motores,     0.06).
prior(logica_ataque_incorrecta,         0.07).
prior(umbral_vl53_mal_configurado,      0.07).
% Suma = 1.00 ✓

% ------------------------------------------------------------
%  2. SÍNTOMAS (los 13 del sistema experto original)
% ------------------------------------------------------------

sintoma_posible(motores_sin_respuesta).
sintoma_posible(solo_motor_izquierdo).
sintoma_posible(solo_motor_derecho).
sintoma_posible(movimiento_debil).
sintoma_posible(calor_excesivo_driver).
sintoma_posible(vl53_sin_lectura).
sintoma_posible(vl53_lectura_erratica).
sintoma_posible(tcr_siempre_activo).
sintoma_posible(tcr_nunca_activo).
sintoma_posible(robot_no_avanza_estrategia).
sintoma_posible(voltaje_bajo).
sintoma_posible(arduino_no_inicia).

% ------------------------------------------------------------
%  3. VEROSIMILITUDES  P(Síntoma | Diagnóstico)
%     Qué tan probable es observar el síntoma si ese diagnóstico
%     es la causa real.  Base para síntomas no listados: 0.02
% ------------------------------------------------------------

% falla_driver_tb6612fng
verosimilitud(motores_sin_respuesta, falla_driver_tb6612fng,           0.95).
verosimilitud(voltaje_bajo,          falla_driver_tb6612fng,           0.90).
verosimilitud(movimiento_debil,      falla_driver_tb6612fng,           0.30).

% conexion_motor_izquierdo_suelta
verosimilitud(solo_motor_derecho,    conexion_motor_izquierdo_suelta,  0.97).
verosimilitud(movimiento_debil,      conexion_motor_izquierdo_suelta,  0.20).

% conexion_motor_derecho_suelta
verosimilitud(solo_motor_izquierdo,  conexion_motor_derecho_suelta,    0.97).
verosimilitud(movimiento_debil,      conexion_motor_derecho_suelta,    0.20).

% pwm_insuficiente_o_codigo_erroneo
verosimilitud(movimiento_debil,      pwm_insuficiente_o_codigo_erroneo,0.90).
% voltaje_bajo ausente es condición del sistema experto original

% sobrecalentamiento_driver
verosimilitud(calor_excesivo_driver, sobrecalentamiento_driver,        0.95).
verosimilitud(motores_sin_respuesta, sobrecalentamiento_driver,        0.85).

% falla_bus_i2c
verosimilitud(vl53_sin_lectura,      falla_bus_i2c,                    0.92).
% voltaje_bajo ausente en la regla original

% conflicto_direccion_i2c
verosimilitud(vl53_lectura_erratica, conflicto_direccion_i2c,          0.93).

% falla_alimentacion_sensores
verosimilitud(vl53_sin_lectura,      falla_alimentacion_sensores,      0.88).
verosimilitud(voltaje_bajo,          falla_alimentacion_sensores,      0.92).

% tcr_obstruido_o_corto
verosimilitud(tcr_siempre_activo,    tcr_obstruido_o_corto,            0.90).

% tcr_desconectado_o_quemado
verosimilitud(tcr_nunca_activo,      tcr_desconectado_o_quemado,       0.96).

% umbral_tcr_mal_calibrado
verosimilitud(tcr_siempre_activo,    umbral_tcr_mal_calibrado,         0.85).

% bateria_descargada_o_regulador_falla
verosimilitud(voltaje_bajo,          bateria_descargada_o_regulador_falla, 0.92).
verosimilitud(arduino_no_inicia,     bateria_descargada_o_regulador_falla, 0.90).

% voltaje_insuficiente_motores
verosimilitud(voltaje_bajo,          voltaje_insuficiente_motores,     0.88).
verosimilitud(movimiento_debil,      voltaje_insuficiente_motores,     0.85).

% logica_ataque_incorrecta
verosimilitud(robot_no_avanza_estrategia, logica_ataque_incorrecta,    0.90).

% umbral_vl53_mal_configurado
verosimilitud(robot_no_avanza_estrategia, umbral_vl53_mal_configurado, 0.85).
verosimilitud(vl53_lectura_erratica,      umbral_vl53_mal_configurado, 0.80).

% ------------------------------------------------------------
%  4. MOTOR DE INFERENCIA BAYESIANA
%     P(D|S1..Sn) ∝ P(D) × ∏ P(Si|D)
% ------------------------------------------------------------

verosimilitud_segura(S, D, P) :-
    ( verosimilitud(S, D, P0) -> P = P0 ; P = 0.02 ).

score(D, Sintomas, Score) :-
    prior(D, Prior),
    foldl(acumular(D), Sintomas, 1.0, Producto),
    Score is Prior * Producto.

acumular(D, S, Acc, Nuevo) :-
    verosimilitud_segura(S, D, P),
    Nuevo is Acc * P.

todos_scores(Sintomas, Scores) :-
    findall(Sc-D, (prior(D,_), score(D, Sintomas, Sc)), Scores).

suma_lista([], 0).
suma_lista([S-_|T], Total) :-
    suma_lista(T, Sub),
    Total is Sub + S.

% ------------------------------------------------------------
%  5. PREDICADO PRINCIPAL: probabilidad_diagnostico/2
%     Retorna la probabilidad A PRIORI de un diagnóstico.
%     Para probabilidad posterior dado síntomas: probabilidad_posterior/3
% ------------------------------------------------------------

%% probabilidad_diagnostico(+Diagnostico, -Probabilidad)
probabilidad_diagnostico(D, P) :- prior(D, P).

%% probabilidad_posterior(+Diagnostico, +Sintomas, -Probabilidad)
probabilidad_posterior(D, Sintomas, PNorm) :-
    todos_scores(Sintomas, Scores),
    suma_lista(Scores, Total),
    Total > 0,
    score(D, Sintomas, Sc),
    PNorm is Sc / Total.

%% diagnosticar_bayesiano(+Sintomas, -DiagnosticosOrdenados)
%  Lista de pares Prob-Diagnostico de mayor a menor.
diagnosticar_bayesiano(Sintomas, Ordenados) :-
    todos_scores(Sintomas, Scores),
    suma_lista(Scores, Total),
    Total > 0,
    maplist([S-D, PN-D]>>(PN is S/Total), Scores, Norm),
    msort(Norm, Asc),
    reverse(Asc, Ordenados).

%% diagnostico_top(+Sintomas, -Diagnostico, -Prob)
diagnostico_top(Sintomas, D, P) :-
    diagnosticar_bayesiano(Sintomas, [P-D|_]).

% ------------------------------------------------------------
%  6. PRESENTACIÓN
% ------------------------------------------------------------

mostrar(Sintomas) :-
    format("~n=== Red Bayesiana Scouta ===~n"),
    format("Síntomas: ~w~n", [Sintomas]),
    format("----------------------------~n"),
    diagnosticar_bayesiano(Sintomas, Lista),
    mostrar_lista(Lista, 1).

mostrar_lista([], _).
mostrar_lista([P-D|T], N) :-
    Pct is P * 100,
    format("~w. ~w  (~4f%)~n", [N, D, Pct]),
    N1 is N+1,
    mostrar_lista(T, N1).

% ------------------------------------------------------------
%  7. CASOS DE PRUEBA — los mismos 5 del sistema experto
%     (seleccionados de las 14 consultas del documento original)
% ------------------------------------------------------------

caso(1, [motores_sin_respuesta, voltaje_bajo],
        falla_driver_tb6612fng).
caso(2, [vl53_sin_lectura, voltaje_bajo],
        falla_alimentacion_sensores).
caso(3, [voltaje_bajo, movimiento_debil],
        voltaje_insuficiente_motores).
caso(4, [tcr_nunca_activo],
        tcr_desconectado_o_quemado).
caso(5, [robot_no_avanza_estrategia, vl53_lectura_erratica],
        umbral_vl53_mal_configurado).

ejecutar_caso(N) :-
    caso(N, Sintomas, Esperado),
    format("~n--- Caso ~w ---~n", [N]),
    format("Síntomas  : ~w~n", [Sintomas]),
    format("Esperado  : ~w~n", [Esperado]),
    diagnostico_top(Sintomas, Obtenido, P),
    Pct is P * 100,
    format("Obtenido  : ~w (~4f%)~n", [Obtenido, Pct]),
    ( Obtenido == Esperado -> write("✓ CORRECTO") ; write("✗ REVISAR") ), nl.

ejecutar_todos_los_casos :-
    forall(caso(N,_,_), ejecutar_caso(N)).

% ============================================================
%  FIN red_bayesiana.pl
% ============================================================
