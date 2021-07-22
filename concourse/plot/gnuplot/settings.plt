set datafile separator ','
set style data histograms
set style histogram rowstacked gap.5 title offset 0, -1
set terminal svg size 5000,1024
set style fill solid
set yrange[0:1500]
set key right
set multiplot layout 3,6
 set label 1 'foo' at graph 0.92,0.9 font ',8'
  plot 'foo.csv' using 2:xtic(1) title 'adsb-payload' with boxes
 set label 1 'bar' at graph 0.92,0.9 font ',8'
  plot 'bar.csv' using 2:xtic(1) title 'ais-payload' with boxes
 set label 1 'baz' at graph 0.92,0.9 font ',8'
  plot 'baz.csv' using 2:xtic(1) title 'aviation' with boxes
