% ============================================================
%  Sistema Experto — Diagnóstico de fallas: Robot Scouta
%  Hardware: Arduino Nano | TB6612FNG | 2x N20 | 2x 18650 7.4V
%            3x VL53L0X | 2x TCR5000
%
%  Descripción:
%    Motor de inferencia hacia adelante basado en reglas.
%    Dado un conjunto de síntomas observados (assert(sintoma/1)),
%    identifica el diagnóstico, explica el razonamiento y
%    entrega una recomendación de acción correctiva.
%
%  Módulos:
%    1. Base de hechos         — hecho/1, hecho/3
%    2. Base de conocimiento   — diagnostico/1  (17 reglas)
%    3. Explicación            — por_que/1
%    4. Recomendaciones        — recomendacion/2
%    5. Motor de inferencia    — diagnosticar/0, diagnosticar_con_fallback/0
%    6. Consulta interactiva   — iniciar/0, ingresar_sintomas/0
%    7. Casos de prueba        — caso/1, todos_los_casos/0
%    8. API JSON               — diagnosticar_json/2
%
%  Uso rápido:
%    ?- consult('scouta_experto_v2.pl').
%    ?- iniciar.
%    ?- assert(sintoma(vl53_lectura_erratica)), diagnosticar.
%    ?- todos_los_casos.
%    ?- caso(3).
% ============================================================

% Síntomas se registran dinámicamente con assert/retract
:- dynamic sintoma/1.
% caso_activo/1 reservado para uso futuro (trazabilidad)
:- dynamic caso_activo/1.

% ============================================================
%  BASE DE HECHOS
%  20 hechos del dominio divididos en:
%    a) Síntomas observables — hecho/1 (átomos que el usuario reporta)
%    b) Constantes del hardware — hecho/3 (nombre, clave, valor)
% ============================================================

% -- Síntomas observables --
% Cada átomo representa una condición que el usuario puede percibir
% directamente en el robot durante o después de una prueba/combate.
hecho(motores_sin_respuesta).       % Ningún motor gira al dar comando
hecho(solo_motor_izquierdo).        % Solo el motor izquierdo responde
hecho(solo_motor_derecho).          % Solo el motor derecho responde
hecho(movimiento_debil).            % Motores giran pero sin fuerza/torque
hecho(calor_excesivo_driver).       % El TB6612FNG está muy caliente al tacto
hecho(vl53_sin_lectura).            % Los VL53L0X no devuelven ningún dato
hecho(vl53_lectura_erratica).       % Los VL53L0X devuelven datos inconsistentes
hecho(tcr5000_siempre_activo).      % Los TCR5000 reportan línea aunque no haya
hecho(tcr5000_nunca_activo).        % Los TCR5000 nunca detectan la línea negra
hecho(robot_no_avanza_estrategia).  % El robot no ejecuta el modo de ataque
hecho(voltaje_bajo).                % Voltaje de la batería por debajo del nominal
hecho(arduino_no_inicia).           % El Arduino Nano no enciende / no ejecuta código
hecho(robot_gira_sin_parar).        % El robot entra en giro continuo sin detenerse
hecho(robot_no_esquiva_borde).      % El robot no reacciona al borde del dohyo
hecho(velocidad_asimetrica).        % Un motor gira más rápido que el otro

% -- Hechos estáticos del dominio (constantes de hardware) --
% Formato: hecho(nombre, clave, valor_numerico_o_atomo)
hecho(voltaje_nominal_bateria_18650_serie, voltaje, 7.4).   % 2x 18650 en serie
hecho(voltaje_minimo_motores_n20,          voltaje, 6.0).   % Mínimo para torque
hecho(voltaje_minimo_arduino_nano,         voltaje, 4.5).   % Mínimo para arranque
hecho(direccion_i2c_vl53l0x,              direccion, 0x29). % Dir. I2C por defecto
hecho(sensores_vl53_cantidad,             cantidad, 3).     % Total de sensores ToF

% ============================================================
%  BASE DE CONOCIMIENTO — 17 reglas de diagnóstico
%
%  Estructura general de cada regla:
%    diagnostico(Nombre) :-
%        sintoma(S1),          % condición necesaria presente
%        \+ sintoma(S2).       % condición que descarta otras causas
%
%  Las negaciones (\+) se usan para distinguir diagnósticos que
%  comparten síntomas pero tienen causas distintas.
% ============================================================

% --- SUBSISTEMA 1: Driver TB6612FNG y motores N20 ---

% Regla 1
% Cuando ambos motores fallan Y hay voltaje bajo → el driver entró
% en modo de protección por VM insuficiente (< 6V).
diagnostico(falla_driver_tb6612fng) :-
    sintoma(motores_sin_respuesta),
    sintoma(voltaje_bajo).

% Regla 2
% Solo el motor derecho funciona Y voltaje normal → el canal izquierdo
% del TB6612FNG recibe la señal pero el motor no la ejecuta.
diagnostico(conexion_motor_izquierdo_suelta) :-
    sintoma(solo_motor_derecho),
    \+ sintoma(voltaje_bajo).

% Regla 3
% Solo el motor izquierdo funciona Y voltaje normal → análogo a regla 2
% pero para el canal derecho del driver.
diagnostico(conexion_motor_derecho_suelta) :-
    sintoma(solo_motor_izquierdo),
    \+ sintoma(voltaje_bajo).

% Regla 4
% Movimiento débil SIN voltaje bajo NI asimetría → los motores reciben
% alimentación correcta pero el PWM configurado es insuficiente.
diagnostico(pwm_insuficiente) :-
    sintoma(movimiento_debil),
    \+ sintoma(voltaje_bajo),
    \+ sintoma(velocidad_asimetrica).

% Regla 5
% Driver caliente Y motores sin respuesta → protección térmica activa.
% El TB6612FNG corta la salida cuando supera ~85°C.
diagnostico(sobrecalentamiento_driver) :-
    sintoma(calor_excesivo_driver),
    sintoma(motores_sin_respuesta).

% Regla 6
% Velocidad asimétrica SIN conexiones sueltas conocidas → los valores
% de PWM para el canal A y canal B del driver son distintos en el código.
diagnostico(desequilibrio_pwm_entre_motores) :-
    sintoma(velocidad_asimetrica),
    \+ sintoma(conexion_motor_izquierdo_suelta),
    \+ sintoma(conexion_motor_derecho_suelta).

% --- SUBSISTEMA 2: Sensores de distancia VL53L0X ---

% Regla 7
% Los 3 VL53L0X no responden Y voltaje normal → el bus I2C está caído.
% Causa típica: falta de resistencias pull-up en SDA/SCL.
diagnostico(falla_bus_i2c) :-
    sintoma(vl53_sin_lectura),
    \+ sintoma(voltaje_bajo).

% Regla 8
% Lecturas erráticas de los VL53L0X → todos tienen la dirección 0x29
% por defecto; si no se inicializan secuencialmente por XSHUT, colisionan.
diagnostico(conflicto_direccion_i2c) :-
    sintoma(vl53_lectura_erratica).

% Regla 9
% Sin lectura de VL53L0X CON voltaje bajo → el regulador 3V3 del Nano
% no puede alimentar los 3 sensores con la batería descargada.
diagnostico(falla_alimentacion_sensores_vl53) :-
    sintoma(vl53_sin_lectura),
    sintoma(voltaje_bajo).

% Regla 10
% Robot no ataca + lecturas erráticas + motores OK → los sensores
% devuelven datos pero el umbral de distancia en el código es incorrecto.
diagnostico(umbral_vl53_mal_configurado) :-
    sintoma(robot_no_avanza_estrategia),
    sintoma(vl53_lectura_erratica),
    \+ sintoma(motores_sin_respuesta).

% --- SUBSISTEMA 3: Sensores de borde TCR5000 ---

% Regla 11
% TCR5000 siempre activo → el pin OUT queda en LOW permanente.
% Causa: lente obstruido, cortocircuito o emisor IR bloqueado.
diagnostico(tcr5000_obstruido_o_corto) :-
    sintoma(tcr5000_siempre_activo).

% Regla 12
% TCR5000 nunca activo → pin OUT queda en HIGH permanente.
% Causa: sensor desconectado, quemado o resistencia incorrecta.
diagnostico(tcr5000_desconectado_o_quemado) :-
    sintoma(tcr5000_nunca_activo).

% Regla 13
% No esquiva el borde PERO los TCR5000 no están en corto → el sensor
% detecta físicamente pero el umbral de lectura en el código es erróneo,
% o la orientación del sensor no apunta al suelo.
diagnostico(riesgo_salida_del_dohyo) :-
    sintoma(robot_no_esquiva_borde),
    \+ sintoma(tcr5000_siempre_activo).

% --- SUBSISTEMA 4: Alimentación (baterías 18650) ---

% Regla 14
% Voltaje bajo + Arduino no inicia → las 2x 18650 están por debajo de
% ~4.5V; el regulador interno del Nano no puede arrancar el microcontrolador.
diagnostico(bateria_descargada) :-
    sintoma(voltaje_bajo),
    sintoma(arduino_no_inicia).

% Regla 15
% Voltaje bajo + movimiento débil + Arduino sigue encendido → el Nano
% funciona (≥4.5V) pero los N20 pierden torque por debajo de 6V.
diagnostico(voltaje_insuficiente_motores) :-
    sintoma(voltaje_bajo),
    sintoma(movimiento_debil),
    \+ sintoma(arduino_no_inicia).

% --- SUBSISTEMA 5: Lógica y estrategia ---

% Regla 16
% Robot no ataca + motores OK + sensores OK → los sensores y actuadores
% funcionan, pero la lógica de decisión del Arduino no activa el ataque.
diagnostico(logica_ataque_incorrecta) :-
    sintoma(robot_no_avanza_estrategia),
    \+ sintoma(motores_sin_respuesta),
    \+ sintoma(vl53_sin_lectura),
    \+ sintoma(vl53_lectura_erratica).

% Regla 17
% Gira sin parar SIN TCR5000 en corto NI lecturas VL53 erráticas →
% la condición de salida del estado de búsqueda nunca se cumple en código.
diagnostico(logica_giro_incorrecta) :-
    sintoma(robot_gira_sin_parar),
    \+ sintoma(tcr5000_siempre_activo),
    \+ sintoma(vl53_lectura_erratica).

% ============================================================
%  MÓDULO DE EXPLICACIÓN — por_que/1
%
%  Dado un diagnóstico, imprime la cadena de razonamiento que
%  llevó a esa conclusión. Usa write/nl para salida estándar.
%  El servidor.pl captura esta salida con with_output_to/2
%  para convertirla en JSON.
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

% Cláusula fallback: diagnóstico sin explicación definida
por_que(D) :-
    write('  [Sin explicacion detallada disponible para: '),
    write(D), write(']'), nl.

% ============================================================
%  RECOMENDACIONES — recomendacion/2
%
%  Formato: recomendacion(Diagnostico, TextoAccion)
%  Cada texto describe la acción física o de código a tomar.
%  El servidor.pl incluye este texto en la respuesta JSON.
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
%  MOTOR DE INFERENCIA — diagnosticar/0
%
%  Itera sobre todos los diagnósticos posibles usando fail/0
%  para forzar el backtracking y encontrar todos los que aplican.
%  Por cada coincidencia imprime: diagnóstico + explicación + acción.
%
%  Prerrequisito: al menos un sintoma/1 debe estar en la base dinámica.
% ============================================================

diagnosticar :-
    write('========================================'), nl,
    write('  Sistema Experto — Robot Scouta v2'), nl,
    write('========================================'), nl, nl,
    ( \+ sintoma(_) ->
        % Guarda de seguridad: no hay síntomas registrados
        write('[!] No hay sintomas registrados. Usa: assert(sintoma(X)).'), nl
    ;
        ( diagnostico(D),
          recomendacion(D, R),
          write('>> DIAGNOSTICO : '), write(D), nl,
          write('   EXPLICACION :'), nl,
          por_que(D),
          write('   ACCION      : '), write(R), nl,
          write('----------------------------------------'), nl,
          fail          % Backtracking forzado para encontrar todos los diagnósticos
        ; true )        % Éxito al agotar todas las alternativas
    ).

% ============================================================
%  FALLBACK — diagnosticar_con_fallback/0
%
%  Wrapper de diagnosticar/0 que maneja el caso en que ninguna
%  regla aplica para los síntomas ingresados.
%  Usado por el servidor HTTP para responder correctamente.
% ============================================================

diagnosticar_con_fallback :-
    write('========================================'), nl,
    write('  Sistema Experto — Robot Scouta v2'), nl,
    write('========================================'), nl, nl,
    ( \+ sintoma(_) ->
        write('[!] No se registraron sintomas.'), nl
    ;
        ( \+ diagnostico(_) ->
            % Ninguna regla coincide con los síntomas dados
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
%  CONSULTA INTERACTIVA — iniciar/0
%
%  Interfaz de línea de comandos para usar el sistema sin el
%  servidor HTTP. Lee síntomas uno por uno hasta recibir "listo."
%  y luego ejecuta el motor de inferencia.
%
%  Flujo:
%    iniciar → retractall(sintoma) → ingresar_sintomas (loop)
%            → diagnosticar_con_fallback
% ============================================================

iniciar :-
    retractall(sintoma(_)),   % Limpia cualquier sesión anterior
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

% Lee síntomas en un loop recursivo hasta que el usuario escribe "listo."
% Cada síntoma válido se agrega a la base dinámica con assert.
ingresar_sintomas :-
    write('Sintoma: '),
    read(X),
    ( X == listo -> true       % Condición de salida del loop
    ; assert(sintoma(X)),
      write('  [OK] Sintoma registrado: '), write(X), nl,
      ingresar_sintomas         % Llamada recursiva para el siguiente síntoma
    ).

% ============================================================
%  CASOS DE PRUEBA — caso/1
%
%  5 escenarios representativos del dominio. Cada caso registra
%  un conjunto de síntomas y ejecuta el motor de inferencia.
%  Diseñados para cubrir los 5 subsistemas del robot.
%
%  Se usan para validar que las reglas funcionan correctamente
%  y también como demo en la interfaz web.
% ============================================================

% Caso 1: Batería descargada en combate
%   Síntomas: voltaje_bajo + arduino_no_inicia
%   Diagnóstico esperado: bateria_descargada
caso(1) :-
    write('=== CASO 1: Bateria descargada en combate ==='), nl,
    retractall(sintoma(_)),
    assert(sintoma(voltaje_bajo)),
    assert(sintoma(arduino_no_inicia)),
    diagnosticar_con_fallback.

% Caso 2: Conflicto I2C en los VL53L0X
%   Síntomas: vl53_lectura_erratica + robot_no_avanza_estrategia
%   Diagnósticos esperados: conflicto_direccion_i2c, umbral_vl53_mal_configurado
caso(2) :-
    write('=== CASO 2: Conflicto I2C en los VL53L0X ==='), nl,
    retractall(sintoma(_)),
    assert(sintoma(vl53_lectura_erratica)),
    assert(sintoma(robot_no_avanza_estrategia)),
    diagnosticar_con_fallback.

% Caso 3: TCR5000 nunca detecta el borde
%   Síntomas: tcr5000_nunca_activo + robot_no_esquiva_borde
%   Diagnósticos esperados: tcr5000_desconectado_o_quemado, riesgo_salida_del_dohyo
caso(3) :-
    write('=== CASO 3: TCR5000 nunca detecta el borde ==='), nl,
    retractall(sintoma(_)),
    assert(sintoma(tcr5000_nunca_activo)),
    assert(sintoma(robot_no_esquiva_borde)),
    diagnosticar_con_fallback.

% Caso 4: Solo gira el motor derecho
%   Síntomas: solo_motor_derecho
%   Diagnóstico esperado: conexion_motor_izquierdo_suelta
caso(4) :-
    write('=== CASO 4: Solo gira el motor derecho ==='), nl,
    retractall(sintoma(_)),
    assert(sintoma(solo_motor_derecho)),
    diagnosticar_con_fallback.

% Caso 5: Robot busca rival pero nunca ataca
%   Síntomas: robot_gira_sin_parar + robot_no_avanza_estrategia
%   Diagnóstico esperado: logica_giro_incorrecta
caso(5) :-
    write('=== CASO 5: Robot busca rival pero nunca ataca ==='), nl,
    retractall(sintoma(_)),
    assert(sintoma(robot_gira_sin_parar)),
    assert(sintoma(robot_no_avanza_estrategia)),
    diagnosticar_con_fallback.

% Ejecuta los 5 casos en secuencia con una línea en blanco entre cada uno
todos_los_casos :-
    caso(1), nl, caso(2), nl, caso(3), nl, caso(4), nl, caso(5).

% ============================================================
%  API JSON — diagnosticar_json/2
%
%  Interfaz para integraciones externas (usada internamente por
%  servidor.pl antes de migrar a findall directo con JSON dicts).
%
%  @param Sintomas  Lista de átomos: [voltaje_bajo, arduino_no_inicia]
%  @param JSON      Dict de salida:
%                   json{status: "ok"|"sin_diagnostico", resultados: [...]}
%
%  Nota: el servidor HTTP actual usa su propio findall en handle_diagnosticar/1.
%  Este predicado se mantiene para compatibilidad y pruebas desde la consola.
% ============================================================

diagnosticar_json(Sintomas, JSON) :-
    retractall(sintoma(_)),
    maplist([S]>>(assert(sintoma(S))), Sintomas),  % Registra todos los síntomas
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
