; SVD01_04
; 
; Programa servocontrol (Slave)
; Por: Alejandro Alonso Puig - mundobot.com
; Fecha: 10/9/2003
; Controlador: 16F876
; Función: 
; Permite control en bucle cerrado de la posición de un motoreductor con 
; entrada de feedback por potenciometro. Básicamente es el programa que
; consigue el funcionamiento como servomotor.
; La comunicación con el exterior se hace mediante bus I2C.
; Adicionalmente se mide el consumo de corriente y temperatura
; Tiene medidas de autoprotección con activación de una señal para ventilación
; en caso de superar una temperatura dada y parada de servomotor en caso de
; superar una temperatura límite.
; Shitches dip para especificar la dirección i2c que se utilizará


	list 		p=16F876
	include		"P16F876.INC"


;Definición de macros

	#define	Ventilador	PORTA,2	;Bit de activación de ventilador
	#define	AlarmaTemp	PORTA,5	;Bit de activación de alarma. El módulo se detiene
					;por exceso de temperatura.
	#define	Version		d'04'	;Versión del programa

;Definición de variables

	cblock	0x20	

	HalfDeadBand	;valor de mitad de banda de precisión de posicionamiento
			;cuanto menor sea, más precisa es la posición
			;DeadBand=2*HalfDeadBand
	PosAct		;Posición actual del servo según Potenciómetro (0 a 255)
	PosNew		;Posicion deseada del servo (0+HalfDeadBand+1 a 255-HalfDeadBand-1)
	PosNewL		;PosNewL y PosNewH son los extremos inferior y superior..
	PosNewH		;..a PosNew para establecer el margen según "DeadBand"
	PosMax		;Valores máximo y mínimo que se puede dar a "PosAct"...
	PosMin		;..en función del HalfDeadBand. Básicamente son..
			;(0+HalfDeadBand+1 a 255-HalfDeadBand-1)

	Corriente	;Consumo de corriente del módulo (ver proc ChkCurrent)
	Temperatura	;Temperatura del módulo de potencia (ver proc ChkTemperatura)
	Estado		;Registro especial de estado del módulo
			;	Bit0: Ventilador On/Off
			;	Bit1: servomotor detenido por exceso de temperatura On/Off
			;	Bits2 y 3: Estado posicionamiento servo. Si ambos On, está
			;		   posicionado. Si solo uno encendido indica que aún
			;		   no está posicionado y el sentido de giro.
			;	Bit7: Indica si el servomotor ha sido detenido por orden i2c

	
	DirNodo		;Dirección I2C de este slave (4 posibles direcciones segun switches dip)
	MensajeIn	;Contendrá el dato recibido por I2C del master
	MensajeOut	;Contendrá el dato a enviar por I2C al master
	BkStatus	;Backup del registro STATUS
	BkW		;Backup W
	Temp		;Variable Temporal usada para evaluación de eventos I2C
	Registro	;Registro accedido por i2c:
			;	1: Registro de Estado. Variable "Estado"
			;	2: No usado. Reservado para velocidad en proximas versiones
			;	3: Posición. En lectura "PosAct" en escritura "PosNew"
			;	4: Temperatura
			;	5: Corriente
			;	6: HalfDeadBand
			;	7: Revisión Firmware. "Version"
	StatI2C		;Registro intermedio para identificar el estado i2c:
			;	0: Si On --> llegó dato Registro (por tanto si llega llega otro
			;		     dato, será para sobreescribir contenido registro dado)


	BDel0		;Usada en retardos		
	BDel1		;Usada en retardos		
	BDel2		;Usada en retardos		
	Pausa		;Usada para hacer pausas con subr "HacerTiempo"

	endc			;Fin de definiciones



	org	0
	goto	INICIO
	org	5		

;-------------------------------------------------------------------------------
Interrupcion   	;RUTINA DE INTERRUPCIÓN. Se ocupa de los eventos I2C
;-------------------------------------------------------------------------------

	;Guardamos copia de algunos registros
	movwf	BkW		;Hace copia de W
	movf	STATUS,W	;Hace copia de registro de estado
	banksel	PORTA
	movwf	BkStatus


	;Chequeamos si la interrupción es por evento I2C. En caso positivo llamamos
	;a la rutina de proceso del evento
	banksel PIR1
	btfss	PIR1,SSPIF	;Ha ocurrido un evento SSP? (I2C)
	goto	IntNoSSP	;No. entonces será por otra cosa. Saltamos.
	call	SSP_Handler	;Si. Procesamos el evento. Si se reciben ordenes, quedarán
				;registradas en "MensajeIn". Se enviarán las ordenes 
				;guardadas en "MensajeOut".
	banksel PIR1
	bcf	PIR1,SSPIF	;Limpiamos el flag
	goto	Rest

IntNoSSP	;Aquí se gestionan interrupciones que no son por SSP

;..........
; En caso de necesitarse, poner aquí la rutina de gestión de interrupciones 
; que no sean por bus I2C
;..........


Rest	;Restauramos las copias de los registros
	movf	BkStatus,W	;Restaura las copias de registros
	movwf	STATUS		;registro de estado
	movf	BkW,W		;registro W

	retfie


;-------------------------------------------------------------------------------


INICIO		;Inicio del cuerpo del programa

	banksel	TRISB		;Apunta a banco 1
	movlw	b'00111100'	;Salida excepto B2, B3, B4 y B5 que tiene switches dip
	movwf	TRISB		;

	;Configuración para uso de conversor A/D
	banksel	ADCON1		
	movlw	b'00001011'	;Establece puerta A como salida excepto RA0 ... 
	movwf	TRISA		;..(Potenciómetro), RA1 (medición corriente) y RA3 (Temperatura)
	movlw	b'00000100'	;PORTA: RA0, RA1, RA3 entrada analog. Resto dig. Justif ADRESH 
	movwf	ADCON1		;
	
	;Inicialización variable de posición del servomotor
	banksel	PosAct
	call	ChkPosAct	;Identificación posición actual del servo..
	movf	PosAct,W	;..y la guardamos en PosNew..
	movwf	PosNew		;..para que el servo no se mueva...

	;Establecemos valor de DeadBand por defecto. Se puede modificar por i2c
	movlw	d'3'
	movwf	HalfDeadBand

	;Establecemos valor registro especial de estado por defecto
	movlw	b'10000000'
	movwf	Estado

	;Configuración para gestión i2c
	call	init_i2c_Slave	;Configuración para uso de i2c
	banksel INTCON
	bsf	INTCON,GIE	;Activamos las interrupciones

	banksel	PORTA
	clrf	PORTA
	clrf	PORTB
	clrf	StatI2C



BUCLE	;Bucle principal del programa

StSt	;Chequeo bit de start/stop del servomotor en registro especial de estado
	btfsc	Estado,7	;On:servomotor funciona, Off:servomotor se detiene
	goto	StON		;Está On. Seguimos
	call	PararMotor	;Está Off. Paramos servomotor,...
	call	ChkPosAct	;..pero seguimos midiendo variables...
	call	ChkCurrent	;..por si son solicitadas por i2c
	call	ChkTemperatura	;Además el ventilador seguira activo si es necesario
	goto	StSt		;y nos mantenemos en bucle hasta que se active por i2c

StON

	;Chequeo Temperatura
	call	ChkTemperatura

	;Chequeo de consumo eléctrico
	call	ChkCurrent

	;Verificamos valor de PosNew para que no sobrepase los límites: 
	;(0+HalfDeadBand+1 a 255-HalfDeadBand-1)
	;Si PosNew > 255-HalfDeadBand-1 then PosNew=255-HalfDeadBand-1
	;Si PosNew < HalfDeadBand+1 then PosNew=HalfDeadBand+1
	movf	HalfDeadBand,W
	addlw	d'1'
	movwf	PosMin		;0+HalfDeadBand+1
	movlw	d'254'
	movwf	PosMax
	movf	HalfDeadBand,W
	subwf	PosMax,F	;255-HalfDeadBand-1

	;Checkea si PosNew > PosMax 
	movf	PosMax,W	;
	subwf	PosNew,W	;Resta/compara con "PosNew" 
	btfsc	STATUS,Z	;Son iguales (Z=1)??
	goto	OkSigue		;Si. Está en el límite de posición, pero es correcto
	btfsc	STATUS,C	;No. Mayor (C=0)??
	goto	FuerzaMax	;Si. (PosNew > PosMax) Forzamos que no pase del límite
	goto	ChkMenos	;No, (PosNew < PosMax)

ChkMenos	;Checkea si PosNew < PosMin
	movf	PosMin,W	;
	subwf	PosNew,W	;Resta/compara con "PosNew" 
	btfsc	STATUS,Z	;Son iguales (Z=1)??
	goto	OkSigue		;Si. Está en el límite de posición, pero es correcto
	btfsc	STATUS,C	;No. Mayor (C=0)??
	goto	OkSigue		;Si. (PosNew > PosMin) está ok: PosMin<PosNew<PosMax
	goto	FuerzaMin	;No, (PosNew < PosMin) Forzamos que no pase del límite

FuerzaMax	;Fuerza a que la posición no pase del máximo
	movf	PosMax,w
	movwf	PosNew
	goto	OkSigue

FuerzaMin	;Fuerza a que la posición no pase del mínimo
	movf	PosMin,W
	movwf	PosNew
	goto	OkSigue

OkSigue	
	
	;Cálculo PosNewH y PosNewL en función del valor de PosNew
	movf	PosNew,W
	movwf	PosNewH
	movwf	PosNewL
	movf	HalfDeadBand,W
	addwf	PosNewH,F
	subwf	PosNewL,F
	
	;Identificación posición actual del servo
	call	ChkPosAct


ChkMayor	;Checkea si PosAct > PosNewH --> Giro antihorario
	movf	PosNewH,W	;
	subwf	PosAct,W	;Resta/compara con "PosAct" 
	btfsc	STATUS,Z	;Son iguales (Z=1)??
	goto	OkPosic		;Si. Está en el límite de DeadBand pero se da por bueno
	btfsc	STATUS,C	;No. Mayor (C=0)??
	goto	GiroAntihora	;Si. (PosAct > PosNewH) Activamos motor
	goto	ChkMenor	;No, (PosAct < PosNewH)

ChkMenor	;Checkea si PosAct < PosNewL --> Giro antihorario
	movf	PosNewL,W	;
	subwf	PosAct,W	;Resta/compara con "PosAct" 
	btfsc	STATUS,Z	;Son iguales (Z=1)??
	goto	OkPosic		;Si. Está en el límite de DeadBand pero se da por bueno
	btfsc	STATUS,C	;No. Mayor (C=0)??
	goto	OkPosic		;Si. (PosAct > PosNewL) está en Deadband:PosNewL< PosAct < PosNewH
	goto	GiroHora	;No, (PosAct < PosNewL) Activamos motor

OkPosic		;Paramos motor
	call	PararMotor
	goto 	BUCLE

GiroHora	;Activamos motor sentido Horario y actualizamos valor registro especial Estado
	bsf	PORTB,0
	bcf	PORTB,1
	bsf	Estado,2
	bcf	Estado,3
	goto 	BUCLE

GiroAntihora	;Activamos motor sentido Antihorario y actualizamos valor registro especial Estado
	bcf	PORTB,0
	bsf	PORTB,1
	bcf	Estado,2
	bsf	Estado,3
	goto 	BUCLE




	goto	BUCLE





;*********************************************************************************
; SUBRUTINAS
;*********************************************************************************


;-------------------------------------------------------------------------------
ChkPosAct		;Identifica la posición actual del servo mediante la
			;la conversión A/D del valor dado por el potenciómetro
			;y lo deja en la variable "PosAct"
;-------------------------------------------------------------------------------

	;Tomaremos datos de ADRESH
	banksel	ADCON1
	bcf	ADCON1,ADFM

	banksel ADCON0
	movlw	b'11000001'	;PORTA-RA0: osci interno, canal-0, activar captura 
	movwf	ADCON0		;
	movlw	d'1'		;Pausa para que de tiempo al condensador interno...
	movwf	Pausa		;..a capturar el valor analógico
	call	HacerTiempo
	bsf	ADCON0,GO	;Comenzar conversión A/D
AD_W1	btfsc	ADCON0,GO_DONE	;Conversión finalizada?	
	goto	AD_W1
	movf	ADRESH,W
	movwf	PosAct		;Guarda en variable de posición actual
	return


;-------------------------------------------------------------------------------
ChkCurrent		;Obtiene el consumo de corriente del módulo servomotor
			;mediante conversión A/D de la caida de potencial de una
			;resistencia de 1 ohm. El valor obtenido se almacena en la 
			;variable "Corriente" de manera que el consumo en amperios
			;se puede calcular con la fórmula siguiente:
			;         Amperios=(Corriente x 0.02)/R
			;siendo R la resistencia de medición, que en principio es de
			;1ohm, pero que conviene medir para que los calculos sean exactos
			;La máxima corriente que puede medir es 255x0.02=5.1 amperios
			;Si la corriente va a ser superior, habra que reducir el valor
			;de la resistencia de manera que Max Amperios x R < 5
;-------------------------------------------------------------------------------


	;Tomaremos datos de ADRESH
	banksel	ADCON1
	bcf	ADCON1,ADFM

	banksel ADCON0
	movlw	b'11001001'	;PORTA-RA1: osci interno, canal-1, activar conversion 
	movwf	ADCON0		;
	movlw	d'1'		;Pausa para que de tiempo al condensador interno...
	movwf	Pausa		;..a capturar el valor analógico
	call	HacerTiempo
	bsf	ADCON0,GO	;Comenzar conversión A/D
AD_W2	btfsc	ADCON0,GO_DONE	;Conversión finalizada?	
	goto	AD_W2
	movf	ADRESH,W
	movwf	Corriente	;Guarda en variable de medición de corriente
	return



;-------------------------------------------------------------------------------
ChkTemperatura		;Obtiene la temperatura del módulo de potencia del servomotor
			;mediante conversión A/D de la salida del sensor LM35
			;y la almacena en la variable "Temperatura"
			;La temperatura en ºC del módulo será igual a:
			;       ºC=(Temperatura/2)+2
;-------------------------------------------------------------------------------


	;Tomaremos datos de ADRESL para tener una precisión de medio grado por bit
	banksel	ADCON1
	bsf	ADCON1,ADFM

	banksel ADCON0
	movlw	b'11011001'	;PORTA-RA3: osci interno, canal-3, activar conversion 
	movwf	ADCON0		;
	movlw	d'1'		;Pausa para que de tiempo al condensador interno...
	movwf	Pausa		;..a capturar el valor analógico
	call	HacerTiempo
	bsf	ADCON0,GO	;Comenzar conversión A/D
AD_W3	btfsc	ADCON0,GO_DONE	;Conversión finalizada?	
	goto	AD_W3
	banksel	ADRESL
	movf	ADRESL,W
	banksel Temperatura
	movwf	Temperatura	;Guarda en variable de medición de temperatura

	;Los drivers utilizados tienen un rango de funcionamiento entre 0º y 70ºC
	;Checkeamos si ha superado 46ºC, con lo que activaríamos ventilador hasta 
	;que baje de 40ºC
	movlw	d'88'		;46ºC=factor 88  --->(88/2)+2=46
	subwf	Temperatura,W	;Resta/compara con "Temperatura" 
	btfsc	STATUS,Z	;Son iguales (Z=1)??
	goto	VentiladorOn	;Si. Activamos ventilador
	btfsc	STATUS,C	;No. Mayor (C=0)??
	goto	VentiladorOn	;Si. Límite de temperatura superado
				;No, verificamos si menor que 40º
	movlw	d'76'		;40ºC=factor 76  --->(76/2)+2=40
	subwf	Temperatura,W	;Resta/compara con "Temperatura" 
	btfsc	STATUS,Z	;Son iguales (Z=1)??
	goto	FinChk		;Si. no hacemos nada. Si ventilador activado, continuará así
	btfsc	STATUS,C	;No. Mayor (C=0)??
	goto	FinChk		;Si. no hacemos nada. Si ventilador activado, continuará así
	goto	VentiladorOff	;No, ha bajado de 40º, podemos desactivar ventilador


VentiladorOn
	bsf	Ventilador	;Activamos ventilador
	bsf	Estado,0	;..y registro especial de estado

	;Checkeamos si ha superado 54ºC, con lo que detendríamos el módulo
	;para evitar sobrecalentamiento hasta que baje de 40ºC
	movlw	d'104'		;54ºC=factor 104  --->(104/2)+2=54
	subwf	Temperatura,W	;Resta/compara con "Temperatura" 
	btfsc	STATUS,Z	;Son iguales (Z=1)??
	goto	AlarmOn		;Si. Activamos procedimiento de alarma por sobrecalentamiento
	btfsc	STATUS,C	;No. Mayor (C=0)??
	goto	AlarmOn		;Si. Límite de temperatura superado
				;No, todo en orden
	goto	FinChk		


VentiladorOff
	bcf	Ventilador	;Paramos ventilador
	bcf	Estado,0	;..y registro especial de estado
	goto	FinChk		


AlarmOn	;Procedimiento ante sobrecalentamiento del módulo

	;Paramos motor
	call	PararMotor

	;Activamos bit de alarma por sobrecalentamiento
	bsf	AlarmaTemp
	bsf	Estado,1	;..y registro especial de estado

ChkT	;Entramos en bucle hasta que baje de 40ºC
	banksel ADCON0
	movlw	b'11011001'	;PORTA-RA3: osci interno, canal-3, activar conversion 
	movwf	ADCON0		;
	movlw	d'1'		;Pausa para que de tiempo al condensador interno...
	movwf	Pausa		;..a capturar el valor analógico
	call	HacerTiempo
	bsf	ADCON0,GO	;Comenzar conversión A/D
AD_W4	btfsc	ADCON0,GO_DONE	;Conversión finalizada?	
	goto	AD_W4
	banksel	ADRESL
	movf	ADRESL,W
	banksel Temperatura
	movwf	Temperatura	;Guarda en variable de medición de temperatura

	movlw	d'76'		;40ºC=factor 76  --->(76/2)+2=40
	subwf	Temperatura,W	;Resta/compara con "Temperatura" 
	btfsc	STATUS,Z	;Son iguales (Z=1)??
	goto	ChkT		;Si. continuamos en bucle hasta que se enfrie
	btfsc	STATUS,C	;No. Mayor (C=0)??
	goto	ChkT		;Si. continuamos en bucle hasta que se enfrie
	bcf	AlarmaTemp	;No, ha bajado de 40º, podemos desactivar condicion alarma
	bcf	Ventilador	;Paramos ventilador
	bcf	Estado,0	;..y registro especial de estado
	goto	FinChk		


FinChk	
	return



;-------------------------------------------------------------------------------
PararMotor		;Detiene el servomotor
;-------------------------------------------------------------------------------
	bsf	PORTB,0
	bsf	PORTB,1
	bsf	Estado,2
	bsf	Estado,3
	return



;-------------------------------------------------------------------------------
init_i2c_Slave		;Inicializa valores para uso de I2C en Slave
			;Ha de ser llamado tras definir TRISC (de ser necesario)
;-------------------------------------------------------------------------------

	;Guardamos copia de algunos registros
	movwf	BkW		;Hace copia de W
	movf	STATUS,W	;Hace copia de registro de estado
	banksel	PORTA
	movwf	BkStatus

	;Establecemos dirección del esclavo segun switches dip (B2 y B3)
	movlw	b'01111000'	
	movwf	DirNodo		
	btfsc	PORTB,2
	bsf	DirNodo,2
	btfsc	PORTB,3
	bsf	DirNodo,1

	;Configuramos I2C
	banksel TRISC		; Pasamos a direccionar Banco 1
	movlw 	b'00011000'	; Establece líneas SDA y SCL como entradas...
	iorwf 	TRISC,F		;..respetando los valores para otras líneas.
	bcf 	SSPSTAT,CKE 	; Establece I2C input levels
	bcf 	SSPSTAT,SMP 	; Habilita slew rate
	bsf	SSPCON2,GCEN	; Habilita direccionamiento global
	banksel	DirNodo
	movf	DirNodo,W	; Dirección esclavo 
	banksel	SSPADD
	movwf	SSPADD		;
	banksel SSPCON 		; Pasamos a direccionar Banco 0
	movlw 	b'00110110'	; Slave mode, SSP enable, 
	movwf 	SSPCON 		; 
	bcf	PIR1,SSPIF	; Limpia flag de eventos SSP
	bcf	PIR1,7		; Limpia bit. Mandatorio por Datasheet

	;Configuración para interrupciones por evento I2C
	banksel PIE1
	bsf	PIE1,SSPIE
	bsf	INTCON,PEIE

	;Restauramos las copias de los registros 
	movf	BkStatus,W	;Restaura las copias de registros
	movwf	STATUS		;registro de estado
	movf	BkW,W		;registro W

	return


; --------------------------------------------------------------------------------------
SSP_Handler	; Este manejador controla cada evento SSP (I2C) acontecido. 
		; El código que se muestra abajo chequea 5 posibles estados.
		; Cada uno de los 5 estados SSP son identificados haciendo 
		; XOR de los bits del registro SSPSTAT con mascaras de bits
		; predeterminadas. Una vez que el estado ha sido identificado
		; se llevan a cabo las acciones pertinentes. Los estados
		; indefinidos son considerados como estados de error.

		; State 1: Operación de escritura I2C, ultimo byte era de dirección.
		; SSPSTAT bits: S = 1, D_A = 0, R_W = 0, BF = 1

		; State 2: Operación de escritura I2C, ultimo byte era de datos.
		; SSPSTAT bits: S = 1, D_A = 1, R_W = 0, BF = 1

		; State 3: Operación de lectura I2C, ultimo byte era de dirección.
		; SSPSTAT bits: S = 1, D_A = 0, R_W = 1, BF = 0

		; State 4: Operación de lectura I2C, ultimo byte era de datos.
		; SSPSTAT bits: S = 1, D_A = 1, R_W = 1, BF = 0

		; State 5: Reset lógico del Slave I2C por NACK del master.
		; SSPSTAT bits: S = 1, D_A = 1, R_W = 0, BF = 0

; --------------------------------------------------------------------------------------


	banksel SSPSTAT
	movf 	SSPSTAT,W 	; Obtiene el valor de SSPSTAT
	andlw 	b'00101101' 	; elimina los bits no importantes SSPSTAT.
	banksel	Temp
	movwf 	Temp 		; para chequeo posterior.

State1: 			; Operación de escritura, ultimo byte ha sido
	movlw 	b'00001001' 	; de dirección, el buffer está lleno.
	banksel	Temp
	xorwf 	Temp,W 		;
	btfss 	STATUS,Z 	; Estamos en el primer estado?
	goto 	State2 		; No, checkeamos siguiente estado
	call 	ReadI2C 	; SI. Hacemos un read SSPBUF (para vaciar buffer).
				; El Hardware se ocupa de mandar Ack
	return

State2: 			; Operación de escritura, ultimo byte ha sido
	movlw 	b'00101001' 	; de datos, el buffer está lleno.
	banksel	Temp
	xorwf 	Temp,W
	btfss 	STATUS,Z 	; Estamos en el segundo estado?
	goto 	State3 		; NO, checkeamos siguiente estado
	call 	ReadI2C 	; SI, Tomamos el byte del SSP.

	;Aquí tenemos en W el valor del dato recibido
	movwf	MensajeIn

	btfsc	StatI2C,0	;Chequeamos si ya sabíamos el registro a actualizar y es un dato
	goto	LoSabemos	;Lo sabíamos, es un dato
	movf	MensajeIn,W	;No lo sabíamos, nos acaba de llegar
	movwf	Registro
	bsf	StatI2C,0
	return

LoSabemos	;Sabemos el registro y tenemos el dato, actualizamos dato del registro
	call	UpdateReg
	bcf	StatI2C,0	;Limpiamos flag
	return

State3: 			; Operación de lectura, ultimo byte ha sido
	movlw 	b'00001100' 	; de dirección, el buffer está vacío
	banksel	Temp
	xorwf 	Temp,W
	btfss 	STATUS,Z 	; Estamos en el tercer estado?
	goto 	State4 		; NO, checkeamos siguiente estado
				; SI

	btfsc	StatI2C,0	;Chequeamos si ya sabemos el registro a leer
	goto	LoSabemosR	;Lo sabemos,
	movlw	0		;No lo sabemos, devolvemos un cero por defecto
	call 	WriteI2C 	;escribimos el byte en SSPBUF
	return
LoSabemosR	;Sabemos el registro a leer. Lo leemos y enviamos el dato
	call	ReadReg
	movf	MensajeOut,W
	call 	WriteI2C 	; SI, escribimos el byte en SSPBUF
	bcf	StatI2C,0	; Limpiamos flag de número de registro recibido
	return

State4: 			; Operación de lectura, ultimo byte ha sido
	movlw 	b'00101100' 	; de datos, el buffer está vacío
	banksel	Temp
	xorwf 	Temp,W
	btfss 	STATUS,Z 	; Estamos en el cuarto estado?
	goto 	State5 		; NO, checkeamos siguiente estado
				; SI. Operación no admitida. 
	movlw	0		; devolvemos un cero por defecto
	call 	WriteI2C 	; escribimos el byte en SSPBUF
	return

State5:
	movlw 	b'00101000' 	; Se ha recibido un NACK mientras se transmitían...
	banksel	Temp
	xorwf 	Temp,W 		; ..datos al master. Lo lógica del Slave..
	btfss 	STATUS,Z 	; ..se resetea en este caso. R_W = 0, D_A = 1
	goto 	I2CErr 		; y BF = 0
	return 			; Si no estamos en State5, entonces es
				; que algo fue mal

I2CErr 	nop			; Algo fue mal
	return


;---------------------------------------------------------------------
WriteI2C	;Usada por SSP_Handler para escribir datos en bus I2C
;---------------------------------------------------------------------

	banksel SSPCON 		
	movwf 	SSPBUF 		; Escribe el dato en W
	bsf 	SSPCON,CKP 	; Libera el reloj
	return

;---------------------------------------------------------------------
ReadI2C		;Usada por SSP_Handler para escribir datos en bus I2C
;---------------------------------------------------------------------

	banksel SSPBUF
	movf 	SSPBUF,W 	; Toma el byte y lo guarda en W
	return


;---------------------------------------------------------------------
UpdateReg		;Actualiza Registro ordenado por I2C
;---------------------------------------------------------------------

	;Procedemos a actuar según la orden recibida del Master. Haremos un Pseudo CASE
	;que actualice solo los registros escribibles e ignore los que no se puedan escribir


M_01	;Estado
	movlw 	d'1'		;
	xorwf 	Registro,W	;
	btfss 	STATUS,Z 	; Es este el registro a actualizar?
	goto 	M_03 		; No, chequeamos siguiente caso
				; Si. procedemos a actualizar el registro (solo bits R/W)
	bsf	Estado,7	; Flag 7: On/Off servomotor
	btfss	MensajeIn,7	; Simplemente establecemos el mismo valor de bit... 
	bcf	Estado,7	; ...que nos ha llegado a "MensajeIn"
	return			;Regresamos a la espera de una nueva orden

M_03	;Posición. En Escritura es PosNew
	movlw 	d'3'		;
	xorwf 	Registro,W	;
	btfss 	STATUS,Z 	; Es este el registro a actualizar?
	goto 	M_06 		; No, chequeamos siguiente caso
	movf	MensajeIn,W 	; Si. procedemos a actualizar el registro
	movwf	PosNew
	return			;Regresamos a la espera de una nueva orden

M_06	;HalfDeadBand
	movlw 	d'6'		;
	xorwf 	Registro,W	;
	btfss 	STATUS,Z 	; Es este el registro a actualizar?
	goto 	M_Error		; No, chequeamos siguiente caso
	movf	MensajeIn,W 	; Si. procedemos a actualizar el registro
	movwf	HalfDeadBand
	return			;Regresamos a la espera de una nueva orden


M_Error	;No es un registro conocido o es de solo lectura. Se ignora.

	return




;---------------------------------------------------------------------
ReadReg		;Leemos Registro solicitado por I2C
;---------------------------------------------------------------------

	;Haremos un Pseudo CASE que lea el registro solicitado y lo deje en MensajeOut


M_01R	;Estado
	movlw 	d'1'		;
	xorwf 	Registro,W	;
	btfss 	STATUS,Z 	; Es este el registro a leer?
	goto 	M_03R 		; No, chequeamos siguiente caso
	movf	Estado,W 	; Si. procedemos a leer el registro
	movwf	MensajeOut
	return			;Regresamos a la espera de una nueva orden

M_03R	;Posición. En Lectura es PosAct
	movlw 	d'3'		;
	xorwf 	Registro,W	;
	btfss 	STATUS,Z 	; Es este el registro a leer?
	goto 	M_04R 		; No, chequeamos siguiente caso
	movf	PosAct,W 	; Si. procedemos a leer el registro
	movwf	MensajeOut
	return			;Regresamos a la espera de una nueva orden

M_04R	;Temperatura
	movlw 	d'4'		;
	xorwf 	Registro,W	;
	btfss 	STATUS,Z 	; Es este el registro a leer?
	goto 	M_05R 		; No, chequeamos siguiente caso
	movf	Temperatura,W 	; Si. procedemos a leer el registro
	movwf	MensajeOut
	return			;Regresamos a la espera de una nueva orden

M_05R	;Corriente
	movlw 	d'5'		;
	xorwf 	Registro,W	;
	btfss 	STATUS,Z 	; Es este el registro a leer?
	goto 	M_06R 		; No, chequeamos siguiente caso
	movf	Corriente,W 	; Si. procedemos a leer el registro
	movwf	MensajeOut
	return			;Regresamos a la espera de una nueva orden

M_06R	;HalfDeadBand
	movlw 	d'6'		;
	xorwf 	Registro,W	;
	btfss 	STATUS,Z 	; Es este el registro a leer?
	goto 	M_07R		; No, chequeamos siguiente caso
	movf	HalfDeadBand,W 	; Si. procedemos a leer el registro
	movwf	MensajeOut
	return			;Regresamos a la espera de una nueva orden

M_07R	;Version
	movlw 	d'7'		;
	xorwf 	Registro,W	;
	btfss 	STATUS,Z 	; Es este el registro a leer?
	goto 	M_ErrorR	; No, chequeamos siguiente caso
	movlw	Version 	; Si. procedemos a leer el registro (en este caso una constante)
	movwf	MensajeOut
	return			;Regresamos a la espera de una nueva orden

M_ErrorR	;No es un registro conocido. Se devuelve valor 0
	clrf	MensajeOut
	return



;---------------------------------------------------------------------------------------
HacerTiempo	;realiza una pausa del numero de centesimas de segundo especificadas en "Pausa"
		;El tiempo real es aproximado, dependiendo del número de interrupciones
		;que se producan.
;---------------------------------------------------------------------------------------

	movf	Pausa,W		;Coloca el valor de pausa en BDel2...
	movwf	BDel2		;...para no alterar su contenido
	
;............................................................
; Generado con PDEL ver SP  r 1.0  el 24/02/03 Hs 18:31:22
; Descripcion: Delay 10000 ciclos (1 centésima de segundo)
;............................................................
BCiclo  movlw     .8        ; 1 set numero de repeticion  (B)
        movwf     BDel0     ; 1 |
BLoop1  movlw     .249      ; 1 set numero de repeticion  (A)
        movwf     BDel1     ; 1 |
BLoop2  nop                 ; 1 nop   
        nop                 ; 1 ciclo delay
        decfsz    BDel1, 1  ; 1 + (1) es el tiempo 0  ? (A)
        goto      BLoop2    ; 2 no, loop
        decfsz    BDel0,  1 ; 1 + (1) es el tiempo 0  ? (B)
        goto      BLoop1    ; 2 no, loop
BDelL1  goto BDelL2         ; 2 ciclos delay
BDelL2  nop                 ; 1 ciclo delay
;............................................................
	decfsz	BDel2,F		;Repite tantas veces el ciclo de una decima de segundo...
	goto	BCiclo		;..como se lo indique BDel2
        return              ; 2+2 Fin.



Fin
	END
