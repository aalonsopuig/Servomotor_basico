<html>

<head>
<meta http-equiv="Content-Language" content="es">
<meta name="GENERATOR" content="Microsoft FrontPage 4.0">
<meta name="ProgId" content="FrontPage.Editor.Document">
</head>

<font size="4"><b><i>Diseño de un servomotor controlado
      por bus I<sup>2</sup>C mediante microcontrolador PIC de gama media</i></b></font>
      <p>Por Alejandro Alonso Puig<br>
      Septiembre 2.003<br>
 <hr>
<p align="justify"><br>
En este repositorio podrás encontrar el código software, vídeo e informe técnico
que describe el diseño, tanto desde el punto de vista
electrónico, como informático de un modelo de servomotor basado en microcontrolador PIC16F876, cuya particularidad
consiste en ser controlado por bus I<sup>2</sup>C. Las características principales del
módulo presentado son las siguientes:&nbsp;</p>
<p align="justify">1. Actúa como Slave permitiendo seleccionar mediante
switches dip la dirección que utilizará en la red I<sup>2</sup>C.&nbsp;</p>
<p align="justify">2. Se puede establecer mediante bus I<sup>2</sup>C tanto la posición
deseada, como el DeadBand&nbsp;</p>
<p align="justify">3. Se puede obtener en todo instante mediante bus I<sup>2</sup>C
el
valor del consumo de corriente del módulo, la temperatura, la posición actual
del eje así como otros ciertos valores de estado&nbsp;</p>
<p align="justify">4. El módulo está protegido para evitar sobrecalentamiento
del mismo mediante sensor de temperatura que activa un mecanismo de ventilación
e incluso la parada del servomotor para evitar daños internos.&nbsp;</p>
<p align="center"><img border="0" src="SVD01.jpg" width="508" height="351"></p>
<p align="justify">La ventaja que se obtiene con este tipo de módulos es
precisamente un control completo por bus I<sup>2</sup>C que hace innecesario tener módulos
específicos para control de servos como ocurre con los de control tipo PWM. De
esta manera pueden controlarse gran cantidad de servos desde un controlador
principal sin apenas sobrecarga en el mismo. Adicionalmente se tienen medida no
habituales, como la de posición real, que permite a nivel de microcontrolador
principal, saber si el servo llegó realmente a su destino o encontró algún
obstáculo que ejercía mayor fuerza que su par. Igualmente la medida de consumo
eléctrico permite conocer cuando el servomotor tiene una sobrecarga de fuerza
contraria a su dirección de movimiento, lo que provoca una subida del consumo
eléctrico medible en este caso.</p>
<br>
<p align="justify">NOTA de 2023: Acabo de subir este proyecto antiguo (de 2003) 
que desarrollé en ensamblador, en mis inicios de aprendizaje de control, por lo que
no aplica un control en bucle cerrado decente, tipo PD o PID.</p>
<br>
<ul>
  <li>
    <p align="justify"><a href="Svd01_docum.pdf">Informe Técnico</a>    <font size="1">(.PDF
    1'9Mb)</font></li>
  <li>
    <p align="justify"><a href="SVD01_04_slave.ASM">Firmware (Programa Slave)</a> <font size="1">(.ASM
    27Kb)</font></li>
  <li>
    <p align="justify"><a href="MSVD04_master.ASM">Programa Master de ejemplo</a> <font size="1">(.ASM
    20Kb)</font></li>
  <li>
    <p align="justify"><a href="SVD01_video.AVI">Video del servo en acción</a><font size="2">
    </font><font size="1">(.AVI 2Mb)</font></li>
</ul>
<p><b>Nota</b>: Master y Slave han de estar conectados mediante tres hilos:
Masa, SCL y SDA. El módulo presentado incluye las resistencias de PullUp, por
lo que no es necesario añadirlas.&nbsp;</p>
<p>
 
<hr>

</body>

</html>
