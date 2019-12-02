#!/bin/bash

#   SIF file to compute in Parallel
#   Changes: Add the ELMERSOLVER_STARTINFO call. DONE
#   Adapt the ElmerGrid to directly call for the partitioner (# partitions). DONE
#   
#   We'll have to adapt it to be able to compute mor ethanone step
#
# File to run the steady state cavity problem
pref="TAU"

# number of the simulation for the same parameter
#num=22
num=$1


######################################
#             WARNING
# MODIFY NAME OF .DAT FILE



# mesh identity - mid 
# -- Regular rectangle --
# 1 - Nx = 50
# 2 - Nx = 100
# 3 - Nx = 200x15
# 4 - Nx = 400
# -- Regular triangle --
# 12 - Nx = 100
# -- 3 domains -- 
# 20 - Nx = 27 38 6   (k1=0.96, a=0.3, dx from 0.1 to 0.3)
# 21 - Nx = 68 202 19 (k1=0.98, a=0.1, dx from 0.025 to 0.1)

mid=3 #
nodes=1
cores=1

# bed roughness - ru (x10) 
rugosite=$2
ru="0"$rugosite
# 5 for 0.05
# 10 for 0.10
# 50 for 0.50
# 100 for 1.0
elx=200
ely=15

muinit=25 
mu_milli=1 # HACK for decimal mu. If mu_milli == 1, 1000 means 0.10 (mu = 10)
mufin=199
mustep=50
# Tau in kilopascals!
tinit=300 # Let's hope this is enough, it's about 9.5° of slope, pas mal
tfin=300

# Hack for the tau
#varaux=$tinit
#varaux=$(echo "$varaux/80" | bc)
tinit=$(echo "scale = 5; 300*(e(1.33333*l($ru/80)))" | bc -l)
#varaux=$(echo "$varaux^1.3333333" | bc)
tinit=$(echo "scale=0;$tinit/1" | bc)

tstep=10000000
plimit=10 # To save time testing

# -----  NO CHANGE BELOW ----
# give where you want to save the run
## Change the scketch path to choose among all *.sif's files
scketchPath=/home/roldanbj/Documents/simulations
midpath=2D/taub_study #SERbig.sif
gitpath=Friction
# Compile the userfucntion and solvers
cd $scketchPath/PROG
#cd /home/roldanbj/BETTIK/simulations/Cavity/PROG/
elmerf90 USF_Exit.F90 -o USF_Exit
elmerf90 USF_fun.F90 -o USF_fun
elmerf90 USF_BedRock.F90 -o USF_BedRock

# Parameters for testing

# IDEA for later: save it in 2e2, 25e1 and such (scientific notation)


# Start the loop in which we create every simulation
for ((mu= muinit; mu <= mufin ; mu= mu+mustep))
do
for ((tau= tinit; tau<= tfin ; tau= tau+tstep))
do
if [ "$mu" -eq 0 ]; then
  scketch=$scketchPath/$gitpath/cavity2dnomu_def.sif #SERbig.sif
else
  scketch=$scketchPath/$gitpath/coulomb_def.sif
fi

# create the run directory
if [ "$mu_milli" -eq 0];then
  dir_name="$midpath/"$pref"_"$num"_"$mid"_m"$mu"_"$ru
else
  dir_name="$midpath/"$pref"_"$num"_"$mid"_m"$(($mu/100))"p"$(($mu%100))"_"$ru
fi
echo "** Name of the run directory:" $dir_name
cd $scketchPath

# Test if this directory already exist
if [ -d $scketchPath/$dir_name ];then
  echo "The directory <"$dir_name"> already exist! Remove it first";
  exit 
fi

mkdir $dir_name

WorkPath=$scketchPath/$dir_name
echo "** working directory:" $WorkPath
cd $WorkPath



# create the mesh
meshName="m"$elx"r"$rugosite
totalmeshName=$WorkPath/"m"$elx"r"$rugosite
meshBase=mesh_blank
#scketchMesh=$scketchPath/MESH/$meshName.grd
scketchMesh=$scketchPath/$gitpath/$meshBase.grd
#cp $scketchMesh $totalmeshName.grd

if [ "$rugosite" -gt 9 ]; then
  cat $scketchMesh | sed -e "s#<elx>#$elx#g"\
                     -e "s#<ely>#$ely#g"\
                     -e "s#<rug>#0.$rugosite#g" > $totalmeshName.grd
else
  cat $scketchMesh | sed -e "s#<elx>#$elx#g"\
                   -e "s#<ely>#$ely#g"\
                   -e "s#<rug>#0.0$rugosite#g" > $totalmeshName.grd
fi

parti=1 # Number of partitions. It must coincide with Nx*Ny*Nz (arguments of partition)
echo "Generating mesh and doing the partition"
ElmerGrid 1 2 $totalmeshName.grd -autoclean # Generates mesh



echo "** Model for the sif:" $scketch
# Run a first simulation for pw=0 (no restart) 
echo "** Run a first simulation for pw=0"

rur="${ru:0:1}.${ru:1:1}" 
# create some needed directories
mkdir sif
mkdir output
mkdir volume


first="!"
after=" "
pw="00"
pwmun="00"


if [ "$mu_milli" -eq 0];then
  name=$pref"_"$num"_"$ind"_m"$mu"_"$ru"_"$pw"_"
  mu_towrite=$mu
else
  name=$pref"_"$num"_"$ind"_m"$(($mu/100))"p"$(($mu%100))"_"$ru"_"$pw"_"
  mu_towrite="$(($mu/100))"."$(($mu%100))"
fi
sifName=$WorkPath/sif/$name.sif

cat $scketch | sed -e "s#<meshName>#$meshName#g"\
                   -e "s#<WorkPath>#$WorkPath#g"\
                   -e "s#<pw>#$pw#g" \
                   -e "s#<pwmun>#$pwmun#g" \
                   -e "s#<pref>#$pref#g" \
                   -e "s#<num>#$num#g" \
                   -e "s#<mid>#$mid#g" \
                   -e "s#<tau>#$tau#g" \
                   -e "s#<first>#$first#g" \
                   -e "s#<after>#$after#g" \
                   -e "s#<mu>#$mu_towrite#g" \
                   -e "s#<ru>#$ru#g" > $sifName

mkdir -p "$WorkPath/OAR"  "$WorkPath/log"

export OARcmd=$WorkPath/OAR/$pw.oar
cat > $OARcmd <<EOF
#!/bin/bash
#OAR -n Run_Elmer
#OAR --stdout $WorkPath/log/Run_$pw.%jobid%.o
#OAR --stderr $WorkPath/log/Run_$pw.%jobid%.e
#OAR --project elmerice
#OAR -l nodes=$nodes/core=$cores,walltime=30:00:00
EOF
# ESSI as in ELMERSOLVER_STARTINFO
ESSIname="startinfo_"$pw

mkdir STARTINFO
cd STARTINFO
mkdir $ESSIname
cd $WorkPath


export sifSI=$WorkPath/STARTINFO/$ESSIname/ELMERSOLVER_STARTINFO
cat > $sifSI <<EOF
$sifName
EOF

ulimit -s unlimited
echo " " >>$OARcmd
echo "cd $WorkPath/STARTINFO/$ESSIname" >>$OARcmd
#--------------------------------------------
if [ $nodes -gt 1 ]; then
   echo "mpirun -np $parti --machinefile ""$""OAR_NODE_FILE -bootstrap-exec oarsh ElmerSolver_mpi > $WorkPath/output/$pw.out" >> $OARcmd
else 
   echo "mpirun -np $parti ElmerSolver_mpi > $WorkPath/output/$pw.out" >> $OARcmd
fi
#--------------------------------------------
echo "cd $WorkPath " >>$OARcmd
echo " " >>$OARcmd

chmod u+x $OARcmd
  cd $WorkPath/STARTINFO/$ESSIname
#  job_id=`oarsub -S $OARcmd |grep OAR_JOB_ID|awk -F'=' '{print $2}'`  
    mpirun -np $parti ElmerSolver_mpi |& tee $WorkPath/output/$pw.out
  cd $WorkPath
echo "Sent job #"$job_id " with pw = "$pw " and tau = "$tau

# Run 80 simulations up to steady state for increasing values of pw/pi (each one restart from the previous)
first=" "
after="!"
pwi=( "00" "01" "02" "03" "04" "05" "06" "07" "08" "09" "10" "11" "12" "13" "14" "15" "16" "17" "18" "19" "20" "21" "22" "23" "24" "25" "26" "27" "28" "29" "30" "31" "32" "33" "34" "35" "36" "37" "38" "39" "40" "41" "42" "43" "44" "45" "46" "47" "48" "49" "50" "51" "52" "53" "54" "55" "56" "57" "58" "59" "60" "61" "62" "63" "64" "65" "66" "67" "68" "69" "70" "71" "72" "73" "74" "75" "76" "77" "78" "79" "80" ) 
for ((i=1 ; i<=$plimit ; i++))
do
    pw=${pwi[$i]}
  # echo "** Create simulation for pw/pi = "$pw "[%]"
  pwmun=${pwi[$i-1]}
if [ "$mu_milli" -eq 0];then
  name=$pref"_"$num"_"$ind"_m"$mu"_"$ru"_"$pw"_"
  mu_towrite=$mu
else
  name=$pref"_"$num"_"$ind"_m"$(($mu/100))"p"$(($mu%100))"_"$ru"_"$pw"_"
  mu_towrite="$(($mu/100))"."$(($mu%100))"
fi

  sifName=$WorkPath/sif/$name.sif

  cat $scketch | sed -e "s#<pw>#$pw#g" \
                     -e "s#<pwmun>#$pwmun#g" \
                     -e "s#<WorkPath>#$WorkPath#g"\
                     -e "s#<pref>#$pref#g" \
                     -e "s#<num>#$num#g" \
                     -e "s#<mid>#$mid#g" \
                     -e "s#<tau>#$tau#g" \
                     -e "s#<first>#$first#g" \
                     -e "s#<after>#$after#g" \
                     -e "s#<meshName>#$meshName#g" \
                     -e "s#<mu>#$mu_towrite#g" \
                     -e "s#<ru>#$ru#g" > $sifName
done

## To be modified with correct way of lanching simulatio oar.. 

for ((i=1 ; i<=$plimit ; i++))
do
  pw=${pwi[$i]}
  export OARcmd=$WorkPath/OAR/$pw.oar

  echo "** Run simulation for pw/pi = "$pw "[%]"
if [ "$mu_milli" -eq 0];then
  name=$pref"_"$num"_"$ind"_m"$mu"_"$ru"_"$pw"_"
  mu_towrite=$mu
else
  name=$pref"_"$num"_"$ind"_m"$(($mu/100))"p"$(($mu%100))"_"$ru"_"$pw"_" 
  mu_towrite="$(($mu/100))"."$(($mu%100))"
fi

  sifName=$WorkPath/sif/$name.sif



cat > $OARcmd <<EOF
#!/bin/bash
#OAR -n Run_Elmer
#OAR --stdout $WorkPath/log/Run_$pw.%jobid%.o
#OAR --stderr $WorkPath/log/Run_$pw.%jobid%.e
#OAR --project elmerice
#OAR -l nodes=$nodes/core=$cores,walltime=30:00:00
EOF
# ESSI as in ELMERSOLVER_STARTINFO
ESSIname="startinfo_"$pw
cd STARTINFO
mkdir $ESSIname
cd $WorkPath

export sifSI=$WorkPath/STARTINFO/$ESSIname/ELMERSOLVER_STARTINFO

cat > $sifSI <<EOF
$sifName
EOF

ulimit -s unlimited

#mpirun -np 4 ElmerSolver_mpi 
cd $WorkPath/STARTINFO/$ESSIname
#ElmerSolver $sifName > $WorkPath/output/$pw.out
echo " " >>$OARcmd
echo "" >>$OARcmd
if [ $nodes -gt 1 ]; then
   echo "mpirun -np $parti --machinefile ""$""OAR_NODE_FILE -bootstrap-exec oarsh ElmerSolver_mpi > $WorkPath/output/$pw.out" >> $OARcmd
else 
   echo "mpirun -np $parti ElmerSolver_mpi > $WorkPath/output/$pw.out" >> $OARcmd
fi
echo "" >>$OARcmd
echo " " >>$OARcmd

  echo "Sent job #"$job_id " with pw = "$pw " and tau = "$tau
  cd $WorkPath/STARTINFO/$ESSIname 
    mpirun -np $parti ElmerSolver_mpi |& tee $WorkPath/output/$pw.out
  cd $WorkPath 
done
echo "Finished with test for tau = " $tau
done
echo "Finished test for mu = " $mu_towrite
done
