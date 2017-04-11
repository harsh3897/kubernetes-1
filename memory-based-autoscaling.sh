#!/bin/bash

heapmem=0
podmem=0
TODAY=`date +%F`
KUBECTL=/usr/local/bin/kubectl
SCRIPT_HOME=/var/log/kube-deploy
if [ ! -d $SCRIPT_HOME ]; then
  mkdir -p $SCRIPT_HOME
fi
#LOG_FILE=$SCRIPT_HOME/kube-$TODAY.log
#touch $LOG_FILE                                                                                                                                                                                           
RED='\033[01;31m'                                                                                                                                                                                          
YELLOW='\033[0;33m'                                                                                                                                                                                        
NONE='\033[00m'                                                                                                                                                                                            
                                                                                                                                                                                                           
print_help(){                                                                                                                                                                                              
  echo -e "${YELLOW}Use the following Command:"                                                                                                                                                            
  echo -e "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"                                                            
  echo -e "${RED}./<script-name> --action <action-name> --deployment <deployment-name> --scaleup <scaleupthreshold> --scaledown <scaledownthreshold>"                                                      
  echo -e "${YELLOW}+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"                                                   
  printf "Choose one of the available actions below:\n"                                                                                                                                                    
  printf " get-heapmemory\n get-podmemory\n deploy-heap-autoscaling\n deploy-pod-autoscaling\n"                                                                                                            
  echo -e "You can get the list of existing deployments using command: kubectl get deployments${NONE}"
}
ARG="$#"
if [[ $ARG -eq 0 ]]; then
  print_help
  exit
fi

while test -n "$1"; do                                                                                                                                                                                     
   case "$1" in                                                                                                                                                                                            
        --action)
            ACTION=$2
            shift
            ;;
        --deployment)
            DEPLOYMENT=$2
            shift
            ;;
        --scaleup)
            SCALEUPTHRESHOLD=$2
            shift
            ;;
        --scaledown)
            SCALEDOWNTHRESHOLD=$2
            shift
            ;;
       *)
            print_help
            exit
            ;;
   esac
    shift
done

LOG_FILE=$SCRIPT_HOME/kube-$DEPLOYMENT-$TODAY.log
touch $LOG_FILE

REPLICAS=`$KUBECTL get deployment -l name=$DEPLOYMENT | awk '{print $3}' | grep -v "CURRENT"`
#########################################
#defining function to calculate heap memory

calculate_heap(){
  echo "===========================" >> $LOG_FILE
  pods=`$KUBECTL get pod -l name=$DEPLOYMENT | awk '{print $1}' | grep -v NAME`
  for i in $pods
    do
      echo "Pod: "$i >> $LOG_FILE

      PID=`$KUBECTL exec -it $i -- ps -ef | grep -v grep | grep java | awk '{print $2}'` >> $LOG_FILE

      TOTALHEAP=`$KUBECTL exec -t $i -- ps -ef | grep java | grep -v grep  | awk -F'Xmx' '{print $2}' | awk '{print $1}' | grep -o '[0-9]\+[a-z]'`
     
      if [[ $TOTALHEAP =~ .*g.* ]]; then
         TOTALHEAPINGB=${TOTALHEAP//[!0-9]/}
         TOTALHEAPINMB=$((TOTALHEAPINGB * 1024))
         echo "Total Heap Capacity Allocated: "$TOTALHEAPINMB"MB" >> $LOG_FILE
      elif [[ $TOTALHEAP =~ .*m.* ]]; then
         TOTALHEAPINMB=${TOTALHEAP//[!0-9]/}
         echo "Total Heap Capacity Allocated: "$TOTALHEAPINMB"MB" >> $LOG_FILE
      fi

      USEDHEAP=`$KUBECTL exec -it $i -- jstat -gc $PID  | tail -n 1 | awk '{ print ($3 + $4 + $6 + $8 + $10) / 1024 }'`
      echo "Used Heap Memory: "$USEDHEAP"MB" >> $LOG_FILE

      UTILIZEDHEAP=$(awk "BEGIN { pc=100*${USEDHEAP}/${TOTALHEAPINMB}; i=int(pc); print (pc-i<0.5)?i:i+1 }")
      echo "Heap memory Percent: "$UTILIZEDHEAP"%" >> $LOG_FILE

      heapmem=$((heapmem+UTILIZEDHEAP))
      echo "===========================" >> $LOG_FILE
    done
  AVGHEAPMEM=$(( $heapmem/$REPLICAS ))
  echo "Average Heap Memory: "$AVGHEAPMEM >> $LOG_FILE
}

#########################################
#defining function to autoscale based on heap memory

heapmemory_autoscale(){
  if [ $AVGHEAPMEM -gt $SCALEUPTHRESHOLD ]
  then
      echo "Memory is greater than the threshold" >> $LOG_FILE
      count=$((REPLICAS+1))
      echo "Updated No. of Replicas will be: "$count >> $LOG_FILE
      scale=`$KUBECTL scale --replicas=$count deployment/$DEPLOYMENT`
      echo "Deployment Scaled Up" >> $LOG_FILE

  elif [ $AVGHEAPMEM -lt $SCALEDOWNTHRESHOLD ] && [ $REPLICAS -gt 2 ]
  then
      echo "Memory is less than threshold" >> $LOG_FILE
      count=$((REPLICAS-1))
      echo "Updated No. of Replicas will be: "$count >> $LOG_FILE
      scale=`$KUBECTL scale --replicas=$count deployment/$DEPLOYMENT`
      echo "Deployment Scaled Down" >> $LOG_FILE
  else
      echo "Heap Memory is not crossing the threshold. No Scaling Done." >> $LOG_FILE
  fi
}

##########################################
#defining function to calculate pod memory

calculate_podmemory(){
pods=`$KUBECTL top pod -l name=$DEPLOYMENT | awk '{print $3}' | grep -o '[0-9]\+'`

TOTALMEM=`$KUBECTL describe pod -l name=$DEPLOYMENT | grep -A 2 "Limits:" | grep memory | grep -o '[0-9]\+[A-Z]' | head -1`
if [[ $TOTALMEM =~ .*G.* ]]; then
    TOTALMEMINGB=${TOTALMEM//[!0-9]/}
    TOTALMEMINMB=$((TOTALMEMINGB * 1024))
    echo "Total Pod Memory Allocated: "$TOTALMEMINMB"MB" >> $LOG_FILE
    echo "===========================" >> $LOG_FILE
elif [[ $TOTALMEM =~ .*M.* ]]; then
    TOTALMEMINMB=${TOTALMEM//[!0-9]/}
    echo "Total Pod Memory Allocated: "$TOTALMEMINMB"MB" >> $LOG_FILE
    echo "===========================" >> $LOG_FILE
fi

for i in $pods
do
  podmem=$((podmem+i))
  echo "Used Pod Memory: "$podmem >> $LOG_FILE
  UTILIZEDPODMEM=$(awk "BEGIN { pc=100*${podmem}/${TOTALMEMINMB}; i=int(pc); print (pc-i<0.5)?i:i+1 }")
  echo "Pod memory Percent: "$UTILIZEDPODMEM"%" >> $LOG_FILE
  echo "===========================" >> $LOG_FILE
done
AVGPODMEM=$(( $UTILIZEDPODMEM/$REPLICAS ))
echo "Average Pod Memory: "$AVGPODMEM >> $LOG_FILE
}

##########################################
#defining function to autoscale based on pod memory

podmemory_autoscale(){
  if [ $AVGPODMEM -gt $SCALEUPTHRESHOLD ]
  then
    echo "Memory is greater than threshold" >> $LOG_FILE
    count=$((REPLICAS+1))
    echo "Updated No. of Replicas will be: "$count >> $LOG_FILE
    scale=`$KUBECTL scale --replicas=$count deployment/$DEPLOYMENT`
    echo "Deployment Scaled Up" >> $LOG_FILE

  elif [ $AVGPODMEM -lt $SCALEDOWNTHRESHOLD ] && [ $REPLICAS -gt 2 ]
  then
    echo "Memory is less than threshold" >> $LOG_FILE
    count=$((REPLICAS-1))
    echo "Updated No. of Replicas will be: "$count >> $LOG_FILE
    scale=`$KUBECTL scale --replicas=$count deployment/$DEPLOYMENT`
    echo "Deployment Scaled Down" >> $LOG_FILE
  else
    echo "Memory is not crossing the threshold. No Scaling done." >> $LOG_FILE
  fi
}

##########################################
#Calling Functions


if [[ $REPLICAS ]]; then
  if [ "$ACTION" = "deploy-heap-autoscaling" ];then
      if [ $ARG -ne 8 ]
      then
        echo "Incorrect No. of Arguments Provided"
        print_help
        exit 1
      fi
      calculate_heap
      heapmemory_autoscale
  elif [ "$ACTION" = "get-heapmemory" ];then
      if [ $ARG -ne 4 ]
      then
        echo "Incorrect No. of Arguments Provided"
        print_help
        exit 1
      fi
      calculate_heap
  elif [ "$ACTION" = "get-podmemory" ];then
      if [ $ARG -ne 4 ]
      then
        echo "Incorrect No. of Arguments Provided"
        print_help
        exit 1
      fi
      calculate_podmemory
  elif [ "$ACTION" = "deploy-pod-autoscaling" ];then
      if [ $ARG -ne 8 ]
      then
        echo "Incorrect No. of Arguments Provided"
        print_help
        exit 1
      fi
      calculate_podmemory
      podmemory_autoscale
  else
      echo "Unknown Action"
      print_help
  fi
else
  echo "No Deployment exists with name: "$DEPLOYMENT
  print_help
fi
