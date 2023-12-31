; MSVD04
; Master para control Servo SVD01_04
; Por: Alejandro Alonso Puig - mundobot.com
; Fecha: 10/9/2003
; Controlador: 16F876
; Funci�n: 
; Controla por I2C el m�dulo servomotor SVD01 v4
; Como ejemplo, mueve el servomotor de un lado al otro y va mostrando el valor del 
; registro de consumo de corriente por barrera de leds conectada
; al puerto B
;
; Las subrutinas definidas para el intercambio de datos con el m�dulo SVD01 (Servomotor)
; son los siguientes:
;
; LECTURA DE REGISTROS
; --------------------
;
; ReadPosSVD01		Obtiene por i2c la posici�n del m�dulo de servomotor 
;			y la deja en la variable "PosActSVD01"
; ReadTempSVD01		Lee el valor de temperatura del m�dulo SVD01 y la deja
;			en "TempSVD01"
; ReadCurrSVD01		Lee el valor de consumo del m�dulo SVD01 
;			y lo deja en la variables "CurrSVD01"
; ReadStatSVD01		Lee el registro de estado del m�dulo SVD01 y lo deja
;			en "StatSVD01"
; ReadHDBSVD01		Obtiene por i2c el registro HalfDeadBand del m�dulo de  
;			servomotor y la deja en la variable "HDBSVD01"
; ReadVerSVD01		Obtiene por i2c la versi�n de firmware del m�dulo de  
;			servomotor y la deja en la variable "VerSVD01"
; 
; ESCRITURA DE REGISTROS
; ----------------------
;
; SetPosSVD01		Ordena por i2c al m�dulo de servomotor que se 
;			coloque en la posici�n establecida por "PosNewSVD01"
; SetStatSVD01		Ordena por i2c al m�dulo de servomotor la actualizaci�n 
;			de su registro especial de estado seg�n el valor de
;			"StatSVD01". Ha de tenerse en cuenta que solo se actualizar�n 
;			aquellos bits que sean R/W. Los dem�s ser�n ignorados.
; SetHDBSVD01		Ordena por i2c al m�dulo de servomotor que almacene 
;			en su registro HalfDeadBand el valor dado por "HDBSVD01"



	list 		p=16F876
	include		"P16F876.INC"


;Definici�n de constantes

	#define	ClockValue 	d'9' 	;(100khz) valor para c�lculo de vel. I2C que pasar� a SSPADD
	#define DirSVD01	b'01111000'	;Direcci�n M�dulo servomotor (01111000)

	;C�digos de registro del m�dulo SVD01
	#define SVD01Stat	d'1'	;Registro de estado
	#define SVD01Posic	d'3'	;Posici�n
	#define SVD01Temp	d'4'	;Temperatura
	#define SVD01Curr	d'5'	;Corriente
	#define SVD01HDB	d'6'	;HalfDeadBand
	#define SVD01Ver	d'7'	;Versi�n del firmware


;Definici�n de variables

	cblock	0x20	
	MensajeIn	;Contendr� el dato recibido por I2C del slave
	MensajeOut	;Contendr� el dato a enviar por I2C al slave
	DirSlave	;Direcci�n del Slave	
	BkStatus	;Backup del registro STATUS 
	BkW		;Backup W

	BDel0		;Usada en retardos		
	BDel1		;Usada en retardos		
	BDel2		;Usada en retardos		
	Pausa		;Usada en para hacer pausas con subr "HacerTiempo"


	;Registros de m�dulo SVD01
	PosActSVD01	;Variable de posici�n actual de servomotor seg�n dato recibido por i2c
	PosNewSVD01	;Posici�n que se desea que tenga la servomotor (2 a 253)
	StatSVD01	;Registro de estado
	TempSVD01	;Temperatura
	CurrSVD01	;Corriente
	HDBSVD01	;HalfDeadBand
	VerSVD01	;Versi�n del firmware


	endc		;Fin de definiciones


	org	0
	goto	INICIO
	org	5		



;-------------------------------------------------------------------------------




INICIO		;Inicio del cuerpo del programa

	banksel	TRISA		;Apunta a banco 1
	movlw	b'00011111'	;Entrada (switches). Solo 5 inferiores
	movwf	TRISA		;
	movlw	b'00000000'	;Salida (Leds)
	movwf	TRISB		;
	banksel	PORTB		;Apunta a banco 0
	clrf	PORTB		;Limpia puerto B
	clrf	PORTA		;Limpia puerto A

	call	init_i2c_Master	;Configuraci�n para uso de i2c

	clrf	MensajeIn
	clrf	MensajeOut

	movlw	d'10'		;Pausa de 10 cent�simas de segundo para que en...
	movwf	Pausa		;...el arranque de tiempo a los slaves a quedar...
	call	HacerTiempo	;..configurados adecuadamente.


MLoop

	;Proceso para resetear el slave en caso de bloqueo de alg�n tipo
	call Send_RStart
	call Send_Stop
	banksel	PORTB

	;Ordena movimiento a posici�n concreta
	movlw	d'255'
	movwf	PosNewSVD01
	call	SetPosSVD01

	;pausa de 50 cent�simas de segundo
	movlw	d'50'
	movwf	Pausa
	call	HacerTiempo

	;Lee registro de corriente del m�dulo servomotor 
	call	ReadCurrSVD01
	movf	CurrSVD01,W
	movwf	PORTB		;muestra en leds de portb

	;pausa de 200 cent�simas de segundo (2 segundos)
	movlw	d'200'
	movwf	Pausa
	call	HacerTiempo

	;Ordena movimiento a posici�n concreta
	movlw	d'0'
	movwf	PosNewSVD01
	call	SetPosSVD01

	;pausa de 200 cent�simas de segundo (2 segundos)
	movlw	d'200'
	movwf	Pausa
	call	HacerTiempo


	goto	MLoop






;*********************************************************************************
; SUBRUTINAS
;*********************************************************************************



;-------------------------------------------------------------------------------
ReadPosSVD01		;Obtiene por i2c la posici�n del m�dulo de servomotor 
			;y la deja en la variable "PosActSVD01"
;-------------------------------------------------------------------------------

	banksel	DirSlave
	movlw	DirSVD01
	movwf	DirSlave
	movlw	SVD01Posic	;Registro 3 de SVD01 	
	movwf	MensajeOut
	call	Send_Start	;Env�a condici�n de inicio
	banksel	DirSlave
	call	Enviar		;Env�a el dato al Slave
	call	Send_RStart	;Env�a condici�n de reinicio
	banksel	DirSlave
	call	Recibir		;Toma dato del Slave...
	movf	MensajeIn,W	;...y lo guarda en...
	movwf	PosActSVD01	;...la variable de registro correspondiente
	call	Send_Stop	;Env�a condici�n de stop
	banksel	DirSlave

	return


;-------------------------------------------------------------------------------
SetPosSVD01		;Ordena por i2c al m�dulo de servomotor que se 
			;coloque en la posici�n establecida por "PosNewSVD01"
;-------------------------------------------------------------------------------

	banksel	DirSlave
	movlw	DirSVD01
	movwf	DirSlave
	movlw	SVD01Posic	;Registro 3 de SVD01	
	movwf	MensajeOut
	call	Send_Start	;Env�a condici�n de inicio
	banksel	DirSlave
	call	Enviar		;Env�a el dato al Slave
	movf	PosNewSVD01,W	;Se deja en W para que...	
	call	Send_Byte	;...Send_Byte lo env�e por i2c
	call	Send_Stop	;Env�a condici�n de stop
	banksel	DirSlave
	return



;-------------------------------------------------------------------------------
ReadTempSVD01		;Lee el valor de temperatura del m�dulo SVD01 y la deja
			;en TempSVD01 
;-------------------------------------------------------------------------------

	;Leemos temperatura en SVD01
	banksel	DirSlave
	movlw	DirSVD01
	movwf	DirSlave
	movlw	SVD01Temp	;Registro 4 de SVD01 (Registro de temperatura)	
	movwf	MensajeOut
	call	Send_Start	;Env�a condici�n de inicio
	banksel	DirSlave
	call	Enviar		;Env�a el dato al Slave
	call	Send_RStart	;Env�a condici�n de reinicio
	banksel	DirSlave
	call	Recibir		;Toma dato del Slave...
	movf	MensajeIn,W	;...y lo guarda en...
	movwf	TempSVD01	;...la variable correspondiente
	call	Send_Stop	;Env�a condici�n de stop
	banksel	DirSlave

	return




;-------------------------------------------------------------------------------
ReadCurrSVD01	;Lee el valor de consumo del m�dulo SVD01 
			;y lo deja en la variables CurrSVD01
;-------------------------------------------------------------------------------

	banksel	DirSlave
	movlw	DirSVD01
	movwf	DirSlave
	movlw	SVD01Curr	;Registro 5 de SVD01 (Registro de Corriente)	
	movwf	MensajeOut
	call	Send_Start	;Env�a condici�n de inicio
	banksel	DirSlave
	call	Enviar		;Env�a el dato al Slave
	call	Send_RStart	;Env�a condici�n de reinicio
	banksel	DirSlave
	call	Recibir		;Toma dato del Slave...
	movf	MensajeIn,W	;...y lo guarda en...
	movwf	CurrSVD01	;...la variable correspondiente
	call	Send_Stop	;Env�a condici�n de stop
	banksel	DirSlave

	return




;-------------------------------------------------------------------------------
ReadStatSVD01		;Lee el registro de estado del m�dulo SVD01 y lo deja
			;en StatSVD01
;-------------------------------------------------------------------------------

	;Leemos registro de estado en MD03_1
	banksel	DirSlave
	movlw	DirSVD01
	movwf	DirSlave
	movlw	SVD01Stat	;Registro 1 de SVD01 (registro de estado)	
	movwf	MensajeOut
	call	Send_Start	;Env�a condici�n de inicio
	banksel	DirSlave
	call	Enviar		;Env�a el dato al Slave
	call	Send_RStart	;Env�a condici�n de reinicio
	banksel	DirSlave
	call	Recibir		;Toma dato del Slave...
	movf	MensajeIn,W	;...y lo guarda en...
	movwf	StatSVD01	;...la variable de registro correspondiente
	call	Send_Stop	;Env�a condici�n de stop
	banksel	DirSlave

	return



;-------------------------------------------------------------------------------
SetStatSVD01		;Ordena por i2c al m�dulo de servomotor la actualizaci�n 
			;de su registro especial de estado seg�n el valor de
			;"StatSVD01". Ha de tenerse en cuenta que solo se actualizar�n 
			;aquellos bits que sean R/W. Los dem�s ser�n ignorados.
;-------------------------------------------------------------------------------

	banksel	DirSlave
	movlw	DirSVD01
	movwf	DirSlave
	movlw	SVD01Stat	;Registro 1 de SVD01 (Estado)	
	movwf	MensajeOut
	call	Send_Start	;Env�a condici�n de inicio
	banksel	DirSlave
	call	Enviar		;Env�a el dato al Slave
	movf	StatSVD01,W	;Se deja en W para que...	
	call	Send_Byte	;...Send_Byte lo env�e por i2c
	call	Send_Stop	;Env�a condici�n de stop
	banksel	DirSlave
	return



;-------------------------------------------------------------------------------
ReadHDBSVD01		;Obtiene por i2c el registro HalfDeadBand del m�dulo de  
			;servomotor y la deja en la variable "HDBSVD01"
;-------------------------------------------------------------------------------

	banksel	DirSlave
	movlw	DirSVD01
	movwf	DirSlave
	movlw	SVD01HDB	;Registro 6 de SVD01 	
	movwf	MensajeOut
	call	Send_Start	;Env�a condici�n de inicio
	banksel	DirSlave
	call	Enviar		;Env�a el dato al Slave
	call	Send_RStart	;Env�a condici�n de reinicio
	banksel	DirSlave
	call	Recibir		;Toma dato del Slave...
	movf	MensajeIn,W	;...y lo guarda en...
	movwf	HDBSVD01	;...la variable de registro correspondiente
	call	Send_Stop	;Env�a condici�n de stop
	banksel	DirSlave

	return


;-------------------------------------------------------------------------------
SetHDBSVD01		;Ordena por i2c al m�dulo de servomotor que almacene 
			;en su registro HalfDeadBand el valor dado por "HDBSVD01"
;-------------------------------------------------------------------------------

	banksel	DirSlave
	movlw	DirSVD01
	movwf	DirSlave
	movlw	SVD01HDB	;Registro 6 de SVD01	
	movwf	MensajeOut
	call	Send_Start	;Env�a condici�n de inicio
	banksel	DirSlave
	call	Enviar		;Env�a el dato al Slave
	movf	HDBSVD01,W	;Se deja en W para que...	
	call	Send_Byte	;...Send_Byte lo env�e por i2c
	call	Send_Stop	;Env�a condici�n de stop
	banksel	DirSlave
	return



;-------------------------------------------------------------------------------
ReadVerSVD01		;Obtiene por i2c la versi�n de firmware del m�dulo de  
			;servomotor y la deja en la variable "VerSVD01"
;-------------------------------------------------------------------------------

	banksel	DirSlave
	movlw	DirSVD01
	movwf	DirSlave
	movlw	SVD01Ver	;Registro 6 de SVD01 	
	movwf	MensajeOut
	call	Send_Start	;Env�a condici�n de inicio
	banksel	DirSlave
	call	Enviar		;Env�a el dato al Slave
	call	Send_RStart	;Env�a condici�n de reinicio
	banksel	DirSlave
	call	Recibir		;Toma dato del Slave...
	movf	MensajeIn,W	;...y lo guarda en...
	movwf	VerSVD01	;...la variable de registro correspondiente
	call	Send_Stop	;Env�a condici�n de stop
	banksel	DirSlave

	return



;-------------------------------------------------------------------------------
init_i2c_Master		;Inicializa valores para uso de I2C en Master
			;Ha de ser llamado tras definir TRISC y un valor para
			;ClockValue. Para frecuencia SCL=Fosc/(4x(ClockValue+1))
;-------------------------------------------------------------------------------

	;Guardamos copia de algunos registros
	movwf	BkW		;Hace copia de W
	movf	STATUS,W	;Hace copia de registro de estado
	banksel	PORTA
	movwf	BkStatus

	;Configuramos I2C
	banksel TRISC		; Pasamos a direccionar Banco 1
	movlw 	b'00011000'	; Establece l�neas SDA y SCL como entradas...
	iorwf 	TRISC,f		;..respetando los valores para otras l�neas.
	movlw 	ClockValue 	; Establece velocidad I2C segun...
	movwf 	SSPADD 		; ...valor de ClockValue 	
	bcf 	SSPSTAT,6 	; Establece I2C input levels
	bcf 	SSPSTAT,7 	; Habilita slew rate
	banksel SSPCON 		; Pasamos a direccionar Banco 0
	movlw 	b'00111000'	; Master mode, SSP enable, velocidad segun...
	movwf 	SSPCON 		; ... Fosc/(4x(SSPADD+1))
	bcf	PIR1,SSPIF	; Limpia flag de eventos SSP
	bcf	PIR1,7		; Limpia bit. Mandatorio por Datasheet

	;Restauramos las copias de los registros
	movf	BkStatus,W	;Restaura las copias de registros
	movwf	STATUS		;registro de estado
	movf	BkW,W		;registro W

	return


; --------------------------------------------------------------------------------------
Enviar	;Env�a un mensaje (comando) almacenado en "MensajeOut" al Slave cuya direcci�n
	;se ha de encontrarse en la variable "DirSlave"
;---------------------------------------------------------------------------------------


	;Guardamos copia de algunos registros
	movwf	BkW		;Hace copia de W
	movf	STATUS,W	;Hace copia de registro de estado
	banksel	PORTA
	movwf	BkStatus

StEnv
	banksel	DirSlave
	movf	DirSlave,W	;Direcci�n esclavo
	call	Send_Byte	;Env�a direcci�n y orden de escritura
	call	WrtAckTest	;Verifica llegada ACK
	banksel SSPCON2 	
	bcf	SSPCON2,ACKSTAT	;limpia flag ACK
	xorlw	1
	btfss	STATUS,Z	;Chequea si lleg� ACK
	goto	SigueEnv	;Si. Seguimos con env�o dato
	call	Send_Stop	;No. Reintentamos env�o
	call	Send_Start	
	goto	StEnv

SigueEnv		
	banksel MensajeOut	
	movf	MensajeOut,W	;Lo deja en W para que la subrutina Send_Byte lo env�e

	call	Send_Byte	;env�a por i2c

	;Restauramos las copias de los registros
	movf	BkStatus,W	;Restaura las copias de registros
	movwf	STATUS		;registro de estado
	movf	BkW,W		;registro W

	return


; --------------------------------------------------------------------------------------
Recibir	;Solicita dato al Slave cuya direcci�n ha de encontrarse en la variable 
	;"DirSlave" y lo mete en "MensajeIn".
;---------------------------------------------------------------------------------------

	;Guardamos copia de algunos registros
	movwf	BkW		;Hace copia de W
	movf	STATUS,W	;Hace copia de registro de estado
	banksel	PORTA
	movwf	BkStatus

StRec	
	banksel	DirSlave
	movf	DirSlave,W	;Direcci�n esclavo
	iorlw	b'00000001'	;con orden de lectura
	call	Send_Byte	;Env�a direcci�n y orden de lectura
	call	WrtAckTest	;Verifica llegada ACK
	banksel SSPCON2 	
	bcf	SSPCON2,ACKSTAT	;limpia flag ACK
	xorlw	1
	btfsc	STATUS,Z	;Chequea si lleg� ACK
	goto	StRec		;No. Reintentamos env�o
				;Si. Leemos dato
	call	Rec_Byte	;Recibe dato por i2c y lo mete en "MensajeIn"

	;Restauramos las copias de los registros
	movf	BkStatus,W	;Restaura las copias de registros
	movwf	STATUS		;registro de estado
	movf	BkW,W		;registro W

	return



; --------------------------------------------------------------------------------------
Send_Start	;Env�a condici�n de start
;---------------------------------------------------------------------------------------

	banksel SSPCON2 		
	bsf 	SSPCON2,SEN 	; Env�a Start
	call	CheckIdle	;Espera fin evento
	return 


; --------------------------------------------------------------------------------------
Send_RStart	;Env�a condici�n de Repeated Start
;---------------------------------------------------------------------------------------

	banksel SSPCON2 		
	bsf 	SSPCON2,RSEN 	; Env�a Repeated Start
	call	CheckIdle	;Espera fin evento
	return 


; --------------------------------------------------------------------------------------
Send_Ack	;Env�a Ack
;---------------------------------------------------------------------------------------

	banksel SSPCON2 	
	bcf 	SSPCON2,ACKDT 	; acknowledge bit state to send (ack)
	bsf 	SSPCON2,ACKEN 	; Inicia secuencia de ack
	call	CheckIdle	;Espera fin evento
	return


; --------------------------------------------------------------------------------------
Send_Nack	;Env�a Nack para finalizar recepci�n
;---------------------------------------------------------------------------------------

	banksel SSPCON2 	
	bsf 	SSPCON2,ACKDT 	; acknowledge bit state to send (not ack)
	bsf 	SSPCON2,ACKEN 	; Inicia secuencia de nack
	call	CheckIdle	;Espera fin evento
	return


; --------------------------------------------------------------------------------------
Send_Stop	;Env�a condici�n de stop
;---------------------------------------------------------------------------------------

	banksel SSPCON2	
	bsf	SSPCON2,PEN	;Activa secuencia de stop
	call	CheckIdle	;Espera fin evento
	return				


; --------------------------------------------------------------------------------------
Send_Byte	;Env�a el contenido de W por i2c
;---------------------------------------------------------------------------------------

	banksel SSPBUF 		; Cambia a banco 0
	movwf 	SSPBUF 		; inicia condicion de escritura
	call	CheckIdle	;Espera fin evento
	return	



; --------------------------------------------------------------------------------------
Rec_Byte	;Recibe dato por i2c y lo mete en "MensajeIn"
;---------------------------------------------------------------------------------------

	banksel SSPCON2 	; Cambia a banco 1
	bsf 	SSPCON2,RCEN 	; genera receive condition
	btfsc 	SSPCON2,RCEN	; espera a que llegue el dato
	goto 	$-1
	banksel SSPBUF		; Cambia a banco 0
	movf 	SSPBUF,w 	; Mueve el dato recibido ...
	movwf 	MensajeIn 	; ...  a MensajeIn
	call	CheckIdle	;Espera fin evento
	return


; --------------------------------------------------------------------------------------
CheckIdle	;Chequea que la operaci�n anterior termino y se puede proceder con
		;el siguiente evento SSP
;---------------------------------------------------------------------------------------

	banksel SSPSTAT		; Cambia a banco 1
	btfsc 	SSPSTAT, R_W 	; Transmisi�n en progreso?
	goto 	$-1
	movf 	SSPCON2,W 		
	andlw 	0x1F 		; Chequeamos con mascara para ver si evento en progreso
	btfss 	STATUS, Z
	goto 	$-3 		; Sigue en progreso o bus ocupado. esperamos
	banksel PIR1		; Cambia a banco 0
	bcf 	PIR1,SSPIF	; Limpiamos flag
	return


;---------------------------------------------------------------------------------------
WrtAckTest	;Chequea ack tras env�o de direcci�n o dato
		;Devuelve en W 0 o 1 dependiendo de si lleg� (0) o no (1) ACK
;---------------------------------------------------------------------------------------

	banksel SSPCON2 	; Cambia a banco 1	
	btfss 	SSPCON2,ACKSTAT ;Chequea llegada ACK desde slave
	retlw	0		;lleg� ACK
	retlw	1		;no lleg� ACK


;---------------------------------------------------------------------------------------
HacerTiempo	;realiza una pausa del numero de centesimas de segundo especificadas en "Pausa"
		
;---------------------------------------------------------------------------------------

	movf	Pausa,W		;Coloca el valor de pausa en BDel2...
	movwf	BDel2		;...para no alterar su contenido
	
;............................................................
; Generado con PDEL ver SP  r 1.0  el 24/02/03 Hs 18:31:22
; Descripcion: Delay 10000 ciclos (1 cent�sima de segundo)
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
	goto	BCiclo		;..como se lo indique ADel2
        return              ; 2+2 Fin.


END
