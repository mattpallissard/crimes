set datafile separator ','
set style data histograms
set style histogram rowstacked gap.5 title offset 0, -1
set terminal svg size 5000,1024
set style fill solid
set yrange[0:1500]
set key right
set multiplot layout 3,6
 set label 1 'adsb-payload' at graph 0.92,0.9 font ',8'
  plot 'adsb-payload.csv' using 2:xtic(1) title 'adsb-payload' with boxes
 set label 1 'ais-payload' at graph 0.92,0.9 font ',8'
  plot 'ais-payload.csv' using 2:xtic(1) title 'ais-payload' with boxes
 set label 1 'aviation' at graph 0.92,0.9 font ',8'
  plot 'aviation.csv' using 2:xtic(1) title 'aviation' with boxes
 set label 1 'blue-ground-services' at graph 0.92,0.9 font ',8'
  plot 'blue-ground-services.csv' using 2:xtic(1) title 'blue-ground-services' with boxes
 set label 1 'constellation' at graph 0.92,0.9 font ',8'
  plot 'constellation.csv' using 2:xtic(1) title 'constellation' with boxes
 set label 1 'data-platform' at graph 0.92,0.9 font ',8'
  plot 'data-platform.csv' using 2:xtic(1) title 'data-platform' with boxes
 set label 1 'gnss-gnd' at graph 0.92,0.9 font ',8'
  plot 'gnss-gnd.csv' using 2:xtic(1) title 'gnss-gnd' with boxes
 set label 1 'guild-sw' at graph 0.92,0.9 font ',8'
  plot 'guild-sw.csv' using 2:xtic(1) title 'guild-sw' with boxes
 set label 1 'infrastructure' at graph 0.92,0.9 font ',8'
  plot 'infrastructure.csv' using 2:xtic(1) title 'infrastructure' with boxes
 set label 1 'maritime' at graph 0.92,0.9 font ',8'
  plot 'maritime.csv' using 2:xtic(1) title 'maritime' with boxes
 set label 1 'optimizer' at graph 0.92,0.9 font ',8'
  plot 'optimizer.csv' using 2:xtic(1) title 'optimizer' with boxes
 set label 1 'platform' at graph 0.92,0.9 font ',8'
  plot 'platform.csv' using 2:xtic(1) title 'platform' with boxes
 set label 1 'red-ground-services' at graph 0.92,0.9 font ',8'
  plot 'red-ground-services.csv' using 2:xtic(1) title 'red-ground-services' with boxes
 set label 1 'sos' at graph 0.92,0.9 font ',8'
  plot 'sos.csv' using 2:xtic(1) title 'sos' with boxes
 set label 1 'space-weather' at graph 0.92,0.9 font ',8'
  plot 'space-weather.csv' using 2:xtic(1) title 'space-weather' with boxes
 set label 1 'srp' at graph 0.92,0.9 font ',8'
  plot 'srp.csv' using 2:xtic(1) title 'srp' with boxes
 set label 1 'tasking' at graph 0.92,0.9 font ',8'
  plot 'tasking.csv' using 2:xtic(1) title 'tasking' with boxes
 set label 1 'testing' at graph 0.92,0.9 font ',8'
  plot 'testing.csv' using 2:xtic(1) title 'testing' with boxes
