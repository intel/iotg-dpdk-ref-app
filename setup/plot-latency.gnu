set datafile separator ','
set terminal pngcairo size 1920,1080
set tmargin 5
set bmargin 5
set lmargin 15
set rmargin 5
set grid
set key center tmargin
set border

set style fill solid 0.25
set boxwidth 0.5
# set logscale y 10

set title "Transmission latency from TX User-space to RX User-space"
set xlabel "Packet count"
set ylabel "Latency in nanoseconds"
plot FILENAME using 7:6 title "Packet Latency"  lc rgb "red" w points
