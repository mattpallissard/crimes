#!/usr/bin/env bash
img_x=5000
img_y=1024
y_min=0
y_max=1500
printf "set datafile separator ','
set style data histograms
set style histogram rowstacked gap.5 title offset 0, -1
set terminal svg size %s,%s
set style fill solid
set yrange[%s:%s]" "$img_x" "$img_y" "$y_min" "$y_max" > settings.plt

for i in *.csv; do
  printf " set label 1 '%s' at graph 0.92,0.9 font ',8'
  plot '%s' using 2:xtic(1) title '%s' with boxes\n" "${i%%.*}" "$i" "${i%%.*}" >> settings.plt
done
