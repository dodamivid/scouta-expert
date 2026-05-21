% ============================================================
%  Sistema Experto — Diagnóstico de fallas: Robot Scouta
%  Proyecto Final — Programación Lógica y Funcional
%  Equipo  : NexCode Solutions
%  Hardware: Arduino Nano | TB6612FNG | 2x N20 | 2x 18650 7.4V
%            3x VL53L0X | 2x TCR5000
% ============================================================

:- dynamic sintoma/1.
:- dynamic caso_activo/1.

% ============================================================
%  BASE DE HECHOS (20 hechos del dominio)
% ============================================================

% -- Síntomas observables --
hecho(motores_sin_respuesta).
hecho(solo_motor_izquierdo).
hecho(solo_motor_derecho).
hecho(movimiento_debil).
hecho(calor_excesivo_driver).
hecho(vl53_sin_lectura).
hecho(vl53_lectura_erratica).
hecho(tcr5000_siempre_activo).
hecho(tcr5000_nunca_activo).
hecho(robot_no_avanza_estrategia).
hecho(voltaje_bajo).
hecho(arduino_no_inicia).
hecho(robot_gira_sin_parar).
hecho(robot_no_esquiva_borde).
hecho(velocidad_asimetrica).

% -- Hechos estáticos del dominio (conocimiento sobre el hardware) --
hecho(voltaje_nominal_bateria_18650_serie, 7.4).
hecho(voltaje_minimo_motores_n20, 6.0).
hecho(voltaje_minimo_arduino_nano, 4.5).
hecho(direccion_i2c_vl53l0x, 0x29).
hecho(sensores_vl53_cantidad, 3).

% ============================================================
%  BASE DE CONOCIMIENTO (15 reglas de diagnóstico)
% ============================================================

% --- SUBSISTEMA 1: Driver TB6612FNG y motores N20 ---

% Regla 1
diagnostico(falla_driver_tb6612fng) :-
    sintoma(motores_sin_respuesta),
    sintoma(voltaje_bajo).

% Regla 2
diagnostico(conexion_motor_izquierdo_suelta) :-
    sintoma(solo_motor_derecho),
    \+ sintoma(voltaje_bajo).

% Regla 3
diagnostico(conexion_motor_derecho_suelta) :-
    sintoma(solo_motor_izquierdo),
    \+ sintoma(voltaje_bajo).

% Regla 4
diagnostico(pwm_insuficiente) :-
    sintoma(movimiento_debil),
    \+ sintoma(voltaje_bajo),
    \+ sintoma(velocidad_asimetrica).

% Regla 5
diagnostico(sobrecalentamiento_driver) :-
    sintoma(calor_excesivo_driver),
    sintoma(motores_sin_respuesta).

% Regla 6 — nueva
diagnostico(desequilibrio_pwm_entre_motores) :-
    sintoma(velocidad_asimetrica),
    \+ sintoma(conexion_motor_izquierdo_suelta),
    \+ sintoma(conexion_motor_derecho_suelta).

% --- SUBSISTEMA 2: Sensores de distancia VL53L0X ---

% Regla 7
diagnostico(falla_bus_i2c) :-
    sintoma(vl53_sin_lectura),
    \+ sintoma(voltaje_bajo).

% Regla 8
diagnostico(conflicto_direccion_i2c) :-
    sintoma(vl53_lectura_erratica).

% Regla 9
diagnostico(falla_alimentacion_sensores_vl53) :-
    sintoma(vl53_sin_lectura),
    sintoma(voltaje_bajo).

% Regla 10 — nueva
diagnostico(umbral_vl53_mal_configurado) :-
    sintoma(robot_no_avanza_estrategia),
    sintoma(vl53_lectura_erratica),
    \+ sintoma(motores_sin_respuesta).

% --- SUBSISTEMA 3: Sensores de borde TCR5000 ---

% Regla 11
diagnostico(tcr5000_obstruido_o_corto) :-
    sintoma(tcr5000_siempre_activo).

% Regla 12
diagnostico(tcr5000_desconectado_o_quemado) :-
    sintoma(tcr5000_nunca_activo).

% Regla 13 — nueva: consecuencia de borde no detectado
diagnostico(riesgo_salida_del_dohyo) :-
    sintoma(robot_no_esquiva_borde),
    \+ sintoma(tcr5000_siempre_activo).

% --- SUBSISTEMA 4: Alimentación (baterías 18650) ---

% Regla 14
diagnostico(bateria_descargada) :-
    sintoma(voltaje_bajo),
    sintoma(arduino_no_inicia).

% Regla 15 — nueva: batería baja sin que el Arduino se apague
diagnostico(voltaje_insuficiente_motores) :-
    sintoma(voltaje_bajo),
    sintoma(movimiento_debil),
    \+ sintoma(arduino_no_inicia).

% --- SUBSISTEMA 5: Lógica y estrategia ---

% Regla 16
diagnostico(logica_ataque_incorrecta) :-
    sintoma(robot_no_avanza_estrategia),
    \+ sintoma(motores_sin_respuesta),
    \+ sintoma(vl53_sin_lectura),
    \+ sintoma(vl53_lectura_erratica).

% Regla 17 — nueva
diagnostico(logica_giro_incorrecta) :-
    sintoma(robot_gira_sin_parar),
    \+ sintoma(tcr5000_siempre_activo),
    \+ sintoma(vl53_lectura_erratica).

% ============================================================
%  MÓDULO DE EXPLICACIÓN — por_que/1
%  Explica al usuario la cadena de razonamiento
% ============================================================

por_que(falla_driver_tb6612fng) :-
    write('  Razon: Se detectaron motores sin respuesta junto con voltaje bajo.'), nl,
    write('  El TB6612FNG entra en modo de proteccion cuando VM < 6V (bateria 18650 descargada).'), nl,
    write('  Conclusion: el driver no puede activar los motores N20.'), nl.

por_que(conexion_motor_izquierdo_suelta) :-
    write('  Razon: Solo el motor derecho funciona y el voltaje es normal.'), nl,
    write('  El TB6612FNG recibe la senal pero el motor izquierdo no responde.'), nl,
    write('  Conclusion: hay una conexion suelta o soldadura fria en el canal izquierdo.'), nl.

por_que(conexion_motor_derecho_suelta) :-
    write('  Razon: Solo el motor izquierdo funciona y el voltaje es normal.'), nl,
    write('  Conclusion: hay una conexion suelta o soldadura fria en el canal derecho.'), nl.

por_que(pwm_insuficiente) :-
    write('  Razon: Los motores giran debilmente sin voltaje bajo ni asimetria.'), nl,
    write('  Los motores N20 necesitan al menos PWM=180/255 bajo carga para generar torque suficiente.'), nl,
    write('  Conclusion: el valor de analogWrite() en el codigo es muy bajo.'), nl.

por_que(sobrecalentamiento_driver) :-
    write('  Razon: El TB6612FNG esta caliente y los motores no responden.'), nl,
    write('  El driver activa proteccion termica cuando supera 85 grados C.'), nl,
    write('  Conclusion: corriente excesiva o falta de disipacion de calor.'), nl.

por_que(desequilibrio_pwm_entre_motores) :-
    write('  Razon: Los motores giran a velocidades diferentes sin falla de conexion.'), nl,
    write('  Conclusion: los valores de PWM para canal A y canal B del TB6612FNG son distintos en el codigo.'), nl.

por_que(falla_bus_i2c) :-
    write('  Razon: Los VL53L0X no devuelven datos y el voltaje es normal.'), nl,
    write('  Los 3 sensores comparten el bus I2C del Arduino Nano.'), nl,
    write('  Conclusion: falta resistencia pull-up de 4.7k en SDA/SCL, o el bus esta en cortocircuito.'), nl.

por_que(conflicto_direccion_i2c) :-
    write('  Razon: Los VL53L0X dan lecturas inconsistentes.'), nl,
    write('  Todos los VL53L0X tienen la misma direccion I2C por defecto (0x29).'), nl,
    write('  Sin inicializacion secuencial via XSHUT, los 3 responden al mismo tiempo y corrompen el bus.'), nl.

por_que(falla_alimentacion_sensores_vl53) :-
    write('  Razon: Los VL53L0X no leen y hay voltaje bajo en el sistema.'), nl,
    write('  Los sensores operan a 3.3V; el pin 3V3 del Nano entrega maximo 50mA para 3 sensores.'), nl,
    write('  Conclusion: bateria descargada o el regulador interno del Nano no entrega suficiente corriente.'), nl.

por_que(umbral_vl53_mal_configurado) :-
    write('  Razon: Los motores funcionan, los VL53L0X leen pero con valores erraticos, y el robot no ataca.'), nl,
    write('  Conclusion: el umbral de distancia en el codigo para detectar al rival es incorrecto.'), nl,
    write('  Ajustar setMeasurementTimingBudget() y la distancia maxima de deteccion.'), nl.

por_que(tcr5000_obstruido_o_corto) :-
    write('  Razon: Los TCR5000 siempre reportan linea detectada aunque no haya linea.'), nl,
    write('  El TCR5000 funciona por reflexion IR: si el emisor o receptor esta obstruido o en corto,'), nl,
    write('  el pin OUT se queda en LOW permanentemente (activo).'), nl.

por_que(tcr5000_desconectado_o_quemado) :-
    write('  Razon: Los TCR5000 nunca detectan la linea negra del borde del dohyo.'), nl,
    write('  Si el sensor esta desconectado, el pin OUT queda flotante o en HIGH permanente.'), nl,
    write('  Conclusion: sensor desconectado, quemado o resistencia limitadora de emisor IR incorrecta.'), nl.

por_que(riesgo_salida_del_dohyo) :-
    write('  Razon: El robot no reacciona al borde pero los TCR5000 no estan cortocircuitados.'), nl,
    write('  Conclusion: el umbral de lectura analogica del TCR5000 en el codigo es incorrecto,'), nl,
    write('  o el sensor no esta correctamente orientado hacia el suelo del dohyo.'), nl.

por_que(bateria_descargada) :-
    write('  Razon: Voltaje bajo y el Arduino Nano no enciende.'), nl,
    write('  Las 2 baterias 18650 en serie entregan 7.4V nominales; por debajo de 6V el Nano se apaga.'), nl,
    write('  Conclusion: las baterias necesitan recarga o reemplazo.'), nl.

por_que(voltaje_insuficiente_motores) :-
    write('  Razon: Voltaje bajo pero el Arduino Nano sigue encendido.'), nl,
    write('  El Nano opera desde 4.5V, pero los motores N20 pierden torque por debajo de 6V.'), nl,
    write('  Conclusion: recargar las baterias 18650 antes del proximo combate.'), nl.

por_que(logica_ataque_incorrecta) :-
    write('  Razon: Motores y sensores funcionan correctamente pero el robot no ataca.'), nl,
    write('  Conclusion: la logica de decision en el codigo Arduino no procesa correctamente'), nl,
    write('  las lecturas de los VL53L0X para activar el modo de ataque.'), nl.

por_que(logica_giro_incorrecta) :-
    write('  Razon: El robot gira sin parar sin que haya linea detectada ni lecturas erraticas de VL53L0X.'), nl,
    write('  Conclusion: la condicion de busqueda (giro continuo) nunca se interrumpe en el codigo;'), nl,
    write('  revisar las condiciones de salida del estado de busqueda.'), nl.

% Fallback: si no hay explicación definida
por_que(D) :-
    write('  [Sin explicacion detallada disponible para: '),
    write(D), write(']'), nl.

% ============================================================
%  RECOMENDACIONES
% ============================================================

recomendacion(falla_driver_tb6612fng,
    'Revisa VM del TB6612FNG (debe ser >= 6V). Mide continuidad en pines AIN1/AIN2/BIN1/BIN2.').
recomendacion(conexion_motor_izquierdo_suelta,
    'Verifica el cable del motor izquierdo en el conector del driver. Revisa soldaduras con multimetro.').
recomendacion(conexion_motor_derecho_suelta,
    'Verifica el cable del motor derecho en el conector del driver. Revisa soldaduras con multimetro.').
recomendacion(pwm_insuficiente,
    'Aumenta el valor de analogWrite() a minimo 180/255 para los motores N20 bajo carga.').
recomendacion(sobrecalentamiento_driver,
    'Deja enfriar el TB6612FNG. Verifica que la corriente de los N20 no supere 1.2A por canal.').
recomendacion(desequilibrio_pwm_entre_motores,
    'Iguala los valores de PWM en el codigo para canal A y canal B del TB6612FNG.').
recomendacion(falla_bus_i2c,
    'Agrega resistencias pull-up de 4.7k entre SDA y 3.3V, y entre SCL y 3.3V. Escanea con i2c_scanner.ino.').
recomendacion(conflicto_direccion_i2c,
    'Inicializa los 3 VL53L0X secuencialmente usando los pines XSHUT para reasignar sus direcciones I2C.').
recomendacion(falla_alimentacion_sensores_vl53,
    'Agrega un regulador AMS1117-3.3 externo para los 3 VL53L0X. Recarga las baterias 18650.').
recomendacion(umbral_vl53_mal_configurado,
    'Ajusta el timing budget con setMeasurementTimingBudget(). Calibra la distancia de deteccion del rival.').
recomendacion(tcr5000_obstruido_o_corto,
    'Limpia el lente del TCR5000. Mide el pin OUT: debe oscilar entre 0V y 3.3V al pasar sobre negro/blanco.').
recomendacion(tcr5000_desconectado_o_quemado,
    'Verifica continuidad del TCR5000. Mide resistencia del emisor IR (~150ohm). Reemplaza si esta quemado.').
recomendacion(riesgo_salida_del_dohyo,
    'Ajusta el umbral de lectura del TCR5000 en el codigo. Verifica que el sensor apunta verticalmente al suelo.').
recomendacion(bateria_descargada,
    'Recarga o reemplaza las 2 baterias 18650. Verifica voltaje en carga: debe ser > 7V.').
recomendacion(voltaje_insuficiente_motores,
    'Recarga las baterias 18650. Los motores N20 necesitan >= 6V para torque completo en combate.').
recomendacion(logica_ataque_incorrecta,
    'Revisa la logica de decision del Arduino: umbrales de distancia VL53L0X y transiciones de estado.').
recomendacion(logica_giro_incorrecta,
    'Revisa la condicion de salida del estado de busqueda en el codigo. Verifica los timeouts de giro.').

% ============================================================
%  MOTOR DE INFERENCIA CON EXPLICACIONES
% ============================================================

diagnosticar :-
    write('========================================'), nl,
    write('  Sistema Experto — Robot Scouta v2'), nl,
    write('========================================'), nl, nl,
    ( \+ sintoma(_) ->
        write('[!] No hay sintomas registrados. Usa: assert(sintoma(X)).'), nl
    ;
        ( diagnostico(D),
          recomendacion(D, R),
          write('>> DIAGNOSTICO : '), write(D), nl,
          write('   EXPLICACION :'), nl,
          por_que(D),
          write('   ACCION      : '), write(R), nl,
          write('----------------------------------------'), nl,
          fail
        ; true )
    ).

% ============================================================
%  FALLBACK — cuando ninguna regla aplica
% ============================================================

diagnosticar_con_fallback :-
    write('========================================'), nl,
    write('  Sistema Experto — Robot Scouta v2'), nl,
    write('========================================'), nl, nl,
    ( \+ sintoma(_) ->
        write('[!] No se registraron sintomas.'), nl
    ;
        ( \+ diagnostico(_) ->
            write('[!] No se encontro ningun diagnostico para los sintomas ingresados.'), nl,
            write('    Posibles causas:'), nl,
            write('    - Combinacion de sintomas no contemplada en la base de conocimiento.'), nl,
            write('    - Verifica si los sintomas fueron escritos correctamente.'), nl,
            write('    - Contacta al tecnico del equipo NexCode Solutions.'), nl
        ;
            diagnosticar
        )
    ).

% ============================================================
%  CONSULTA INTERACTIVA
% ============================================================

iniciar :-
    retractall(sintoma(_)),
    write('========================================='), nl,
    write('  Diagnostico interactivo — Robot Scouta '), nl,
    write('========================================='), nl,
    write('Sintomas disponibles:'), nl,
    write('  motores_sin_respuesta    solo_motor_izquierdo'), nl,
    write('  solo_motor_derecho       movimiento_debil'), nl,
    write('  calor_excesivo_driver    vl53_sin_lectura'), nl,
    write('  vl53_lectura_erratica    tcr5000_siempre_activo'), nl,
    write('  tcr5000_nunca_activo     robot_no_avanza_estrategia'), nl,
    write('  voltaje_bajo             arduino_no_inicia'), nl,
    write('  robot_gira_sin_parar     robot_no_esquiva_borde'), nl,
    write('  velocidad_asimetrica'), nl, nl,
    write('Ingresa un sintoma por linea. Escribe "listo." para diagnosticar.'), nl, nl,
    ingresar_sintomas,
    nl,
    diagnosticar_con_fallback.

ingresar_sintomas :-
    write('Sintoma: '),
    read(X),
    ( X == listo -> true
    ; assert(sintoma(X)),
      write('  [OK] Sintoma registrado: '), write(X), nl,
      ingresar_sintomas
    ).

% ============================================================
%  CASOS DE PRUEBA — 5 casos distintos del dominio
% ============================================================

caso(1) :-
    write('=== CASO 1: Bateria descargada en combate ==='), nl,
    retractall(sintoma(_)),
    assert(sintoma(voltaje_bajo)),
    assert(sintoma(arduino_no_inicia)),
    diagnosticar_con_fallback.

caso(2) :-
    write('=== CASO 2: Conflicto I2C en los VL53L0X ==='), nl,
    retractall(sintoma(_)),
    assert(sintoma(vl53_lectura_erratica)),
    assert(sintoma(robot_no_avanza_estrategia)),
    diagnosticar_con_fallback.

caso(3) :-
    write('=== CASO 3: TCR5000 nunca detecta el borde ==='), nl,
    retractall(sintoma(_)),
    assert(sintoma(tcr5000_nunca_activo)),
    assert(sintoma(robot_no_esquiva_borde)),
    diagnosticar_con_fallback.

caso(4) :-
    write('=== CASO 4: Solo gira el motor derecho ==='), nl,
    retractall(sintoma(_)),
    assert(sintoma(solo_motor_derecho)),
    diagnosticar_con_fallback.

caso(5) :-
    write('=== CASO 5: Robot busca rival pero nunca ataca ==='), nl,
    retractall(sintoma(_)),
    assert(sintoma(robot_gira_sin_parar)),
    assert(sintoma(robot_no_avanza_estrategia)),
    diagnosticar_con_fallback.

todos_los_casos :-
    caso(1), nl, caso(2), nl, caso(3), nl, caso(4), nl, caso(5).

% ============================================================
%  API JSON — para conectar con la interfaz web
%  Recibe lista de sintomas, devuelve diagnosticos como JSON
% ============================================================

diagnosticar_json(Sintomas, JSON) :-
    retractall(sintoma(_)),
    maplist([S]>>(assert(sintoma(S))), Sintomas),
    findall(
        diagnostico{id: D, recomendacion: R},
        ( diagnostico(D), recomendacion(D, R) ),
        Resultados
    ),
    ( Resultados = [] ->
        JSON = json{status: "sin_diagnostico", resultados: []}
    ;
        JSON = json{status: "ok", resultados: Resultados}
    ).

% ============================================================
%  USO RÁPIDO
% ============================================================
%
%  ?- consult('scouta_experto_v2.pl').
%
%  Interactivo:
%  ?- iniciar.
%
%  Directo:
%  ?- assert(sintoma(vl53_lectura_erratica)), diagnosticar.
%
%  Casos de prueba:
%  ?- todos_los_casos.
%  ?- caso(3).
%
