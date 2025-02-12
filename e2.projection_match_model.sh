#!/bin/bash
#
#
############################################################################
#
# Author: "Kyle L. Morris"
# MRC London Institute of Medical Sciences 2019
#
# This program is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 3 of the License, or
#     (at your option) any later version.
#
#     This program is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
############################################################################

modelin=$2
box=$3
res=$4
apix=$5
classes=$1

# Source eman2
module load eman2
# Test if eman2 is sourced and available
command -v e2.py >/dev/null 2>&1 || { echo >&2 "Eman2 does not appear to be installed or loaded..."; exit 1; }

# Test for input variables
if [[ -z $1 ]] || [[ -z $2 ]] || [[ -z $3 ]] || [[ -z $4 ]] || [[ -z $5 ]] ; then
  echo ""
  echo "Variables empty, usage is $(basename $0) (1) (2) (3) (4) (5)"
  echo ""
  echo "(1) = class for comparison"
  echo "(2) = model for comparison"
  echo "(3) = box size"
  echo "(4) = resolution"
  echo "(5) = pixel size"
  echo ""

  exit
fi

# Directory and folder names
ext=$(echo ${classes##*.})
name=$(basename $classes .${ext})
dir=$(dirname $classes)

############################################################################
# Set up projections and do matching
############################################################################

# Make volume from model
e2pdb2mrc.py --center --apix ${apix} --res ${res} --box ${box} ${modelin} ${name}_${res}A_${box}px.mrc

# Single projection from volume for test matching
#e2project3d.py -f ../emd_8236_scaled_1p07_256px.mrc --outfile=projection.mrc --orientgen=single:alt=20.00:az=146.19 --projector=standard --verbose=2

# Match volume to projection
e2classvsproj.py --aligncmp=frc --cmp=frc --threads 4 --savesim ${name}_${res}A_${box}px_proj_match.txt \
${classes} ${name}_${res}A_${box}px.mrc ${name}_${res}A_${box}px_proj_match.mrcs

# Save some info that is helpful
echo "$(basename $0) run information:" > ${name}_${res}A_${box}px_proj_match.log
echo "" >> ${name}_${res}A_${box}px_proj_match.log
echo "class for comparison:  ${classes}" >> ${name}_${res}A_${box}px_proj_match.log
echo "model for comparison:  ${modelin}" >> ${name}_${res}A_${box}px_proj_match.log
echo "box size:              ${box}" >> ${name}_${res}A_${box}px_proj_match.log
echo "resolution:            ${res}" >> ${name}_${res}A_${box}px_proj_match.log
echo "pixel size:            ${apix}" >> ${name}_${res}A_${box}px_proj_match.log
echo "" >> ${name}_${res}A_${box}px_proj_match.log

############################################################################
# Find best matching projection and pull out x,y,z for orienting model in chimera etc
############################################################################

input="${name}_${res}A_${box}px_proj_match.txt"

# Find angles of top projection match
cat ${input} | sort -g -k 5 | head -n 1
az=$(cat ${input} | sort -g -k 5 | head -n 1 | awk '{print $4}')
alt=$(cat ${input} | sort -g -k 5 | head -n 1 | awk '{print $3}')
sim=$(cat ${input} | sort -g -k 5 | head -n 1 | awk '{print $5}')
echo ""
echo "eman az: ${az}"
echo "eman alt: ${alt}"
echo "eman FRC: ${sim}"

# Convert into x, y, z chimera command
# See https://groups.google.com/forum/?utm_medium=email&utm_source=footer#!msg/eman2/3HEMbPtcGOg/2qqCxfPoCQAJ
e2.py <<EOF > .python.out
import sys
sys.stdout = open('xyz.dat', 'w')
print(Transform({"type":"eman","az":${az},"alt":${alt},"phi":0}).get_rotation("xyz"))
print(Transform({"type":"eman","az":${az},"alt":${alt},"phi":0}).inverse().get_rotation("xyz"))
EOF

# Get the x,y,z data out of xyz.dat
xtilt=$(cat xyz.dat | sed -n 2p | awk {'print $4'} | sed 's/,//g')
ytilt=$(cat xyz.dat | sed -n 2p | awk {'print $6'} | sed 's/,//g')
ztilt=$(cat xyz.dat | sed -n 2p | awk {'print $8'} | sed 's/,//g')
echo ""
echo "Normal:"
echo "xtilt=${xtilt}:ytilt=${ytilt}:ztilt=${ztilt}"

xtiltinv=$(cat xyz.dat | sed -n 4p | awk {'print $4'} | sed 's/,//g')
ytiltinv=$(cat xyz.dat | sed -n 4p | awk {'print $6'} | sed 's/,//g')
ztiltinv=$(cat xyz.dat | sed -n 4p | awk {'print $8'} | sed 's/,//g')
echo ""
echo "Inverted:"
echo "xtilt=${xtiltinv}:ytilt=${ytiltinv}:ztilt=${ztiltinv}"
echo ""

# Tidy up
rm -rf xyz.dat

# Print chimera commands
# -X,Y,Z becomes Z,Y,X if you operate on the coordinate system rather than the object

echo "Standard euler angle conversion:"
echo ""
i=$(echo "scale=0; ${xtilt}/1" | bc)
if [[ ${i} -lt 0 ]] ; then
  rotorder="Z,Y,X"
  command="reset; turn z ${ztilt}; turn y ${ytilt}; turn x ${xtilt}; focus"
  xtilt=$(echo ${xtilt}*-1 | bc)
  echo "Detected negative xtilt, changing -X,Y,Z to Z,Y,X"
  echo "Chimera commands:"
  echo ${command}
  echo ""
else
  rotorder="X,Y,Z"
  command="reset; turn x ${xtilt}; turn y ${ytilt}; turn z ${ztilt}; focus"
  echo "Positive xtilt, angle convention is X,Y,Z"
  echo "Chimera commands:"
  echo ${command}
  echo ""
fi

echo "Inverted euler angle conversion:"
echo ""
i=$(echo "scale=0; ${xtiltinv}/1" | bc)
if [[ ${i} -lt 0 ]] ; then
  commandinv="reset; turn z ${ztiltinv}; turn y ${ytiltinv}; turn x ${xtiltinv}; focus"
  xtiltinv=$(echo ${xtiltinv}*-1 | bc)
  echo "Detected negative xtilt, changing -X,Y,Z to Z,Y,X"
  echo "Chimera commands:"
  echo ${commandinv}
  echo ""
else
  commandinv="reset; turn x ${xtiltinv}; turn y ${ytiltinv}; turn z ${ztiltinv}; focus"
  echo "Positive xtilt, angle convention is X,Y,Z"
  echo "Chimera commands:"
  echo ${commandinv}
  echo ""
fi

# Save some info that is helpful
echo "Projection match (eman2):" >> ${name}_${res}A_${box}px_proj_match.log
echo "eman az:  ${az}" >> ${name}_${res}A_${box}px_proj_match.log
echo "eman alt: ${alt}" >> ${name}_${res}A_${box}px_proj_match.log
echo "FRC:      ${sim}" >> ${name}_${res}A_${box}px_proj_match.log
echo "" >> ${name}_${res}A_${box}px_proj_match.log

echo "Rotation commands (UCSF Chimera):" >> ${name}_${res}A_${box}px_proj_match.log
echo "Rotation order: ${rotorder}" >> ${name}_${res}A_${box}px_proj_match.log
echo ${command} >> ${name}_${res}A_${box}px_proj_match.log
echo ${commandinv} >> ${name}_${res}A_${box}px_proj_match.log

# Make a chimera script
echo "open ${dir}/${name}_${res}A_${box}px.mrc" > ${name}_${res}A_${box}px_proj_match.com
echo "volume #0 origin 0 transparency 0.66" >> ${name}_${res}A_${box}px_proj_match.com
echo "open ${dir}/${modelin}" >> ${name}_${res}A_${box}px_proj_match.com
echo "${command}"  >> ${name}_${res}A_${box}px_proj_match.com
echo "savepos p1"  >> ${name}_${res}A_${box}px_proj_match.com
echo "matrixget ${dir}/${name}_${res}A_${box}px_proj_match_matrix_p1"  >> ${name}_${res}A_${box}px_proj_match.com
echo "${commandinv}"  >> ${name}_${res}A_${box}px_proj_match.com
echo "savepos p2"  >> ${name}_${res}A_${box}px_proj_match.com
echo "matrixget ${dir}/${name}_${res}A_${box}px_proj_match_matrix_p2"  >> ${name}_${res}A_${box}px_proj_match.com
echo "focus"  >> ${name}_${res}A_${box}px_proj_match.com

# Show the projection
e2display.py ${classes} &
e2display.py ${name}_${res}A_${box}px_proj_match.mrcs &
