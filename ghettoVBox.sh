#!/bin/sh
# Author: Seweryn Walentynowicz <S.Walentynowicz@walor.torun.pl>
# Created Date: 8.10.2018
# inspired by ghettoVCB by William Lam

##################################################################
#                   User Definable Parameters
##################################################################

LAST_MODIFIED_DATE="16.10.2018"
VERSION=0.4

# directory that all VM backups should go 
VM_BACKUP_VOLUME=""



##################################################################
#                   End User Definable Parameters
##################################################################

########################## DO NOT MODIFY PAST THIS LINE #######################

LOG_LEVEL="info"
# name of VM to backup
VM2BACKUP=""

printUsage() {
        echo "###############################################################################"
        echo "#"
        echo "# ghettoVBox for VirtualBox 4.x 5.x"
        echo "# Author: Seweryn Walentynowicz"
        echo "# Created: 8.10.2018"
        echo "# Last modified: ${LAST_MODIFIED_DATE} Version ${VERSION}"
        echo "#"
        echo "###############################################################################"
        echo
        echo "Usage: $(basename $0) [options]"
        echo
        echo "OPTIONS:"
	echo "   -m     Name of VM to backup (overrides -f)"
	echo "   -p     Backup pool directory name"
        echo "   -l     File to output logging"
        echo "   -d     Debug level [info|debug|dryrun] (default: info)"
	echo "   -h     This help"
        echo
	echo " options -m and -p must be set"
        echo
}

logger() {
    LOG_TYPE=$1
    MSG=$2

    if [[ "${LOG_LEVEL}" == "debug" ]] && [[ "${LOG_TYPE}" == "debug" ]] || [[ "${LOG_TYPE}" == "info" ]] || [[ "${LOG_TYPE}" == "dryrun" ]]; then
        TIME=$(date +%F" "%H:%M:%S)
        if [[ "${LOG_TO_STDOUT}" -eq 1 ]] ; then
            echo -e "${TIME} -- ${LOG_TYPE}: ${MSG}"
        fi

        if [[ -n "${LOG_OUTPUT}" ]] ; then
            echo -e "${TIME} -- ${LOG_TYPE}: ${MSG}" >> "${LOG_OUTPUT}"
        fi

    fi
}


#########################
#                       #
# Start of Main Script  #
#                       #
#########################

#read user input
while getopts ":m:p:l:hd:" ARGS; do
    case $ARGS in
	m)  VM2BACKUP="${OPTARG}"
            ;;
	p)  VM_BACKUP_VOLUME="${OPTARG}"
            ;;  
        l)
            LOG_OUTPUT="${OPTARG}"
            ;;
        d)
            LOG_LEVEL="${OPTARG}"
            ;;
	h)  printUsage
	    exit 0
	    ;;
        :)
            echo "Option -${OPTARG} requires an argument."
            exit 1
            ;;
        *)
            printUsage
            ;;
    esac
done

# tylko na testy
#echo LOG_LEVEL=${LOG_LEVEL}
#echo LOG_OUTPUT=${LOG_OUTPUT}

# =============== część partykularna na szybko =================

BACKUPPOOL=${VM_BACKUP_VOLUME}

VBOXCOMMAND="VBoxManage"
TEMP_SNAPSHOT_NAME=VBGHETTO`date +%Y%d%m%H%M%S`
BACKUP_DIR=${BACKUPPOOL}/${VM2BACKUP}/`date +%F_%H-%M-%S`

# 0. 
# Testowanie czy jest zdefiniowany katalog na backupy w ogóle
if [[ -z "${VM_BACKUP_VOLUME}" ]] ; then
        echo "Virtal machine pool directory is not set !!!"
        exit 1
fi
# Testowanie czy podana nazwa odpowiada maszynie wirtualnej
function VMExists() {
	VM_TO_SEARCH=$1
	
	isVMFound=0
	FOUND=$( ${VBOXCOMMAND} list vms |awk /\"${VM_TO_SEARCH}\"/'{print "1"}')
        if [[ ${FOUND} == "1" ]] ; then
                isVMFound=1
        fi

}
if [[ -z "${VM2BACKUP}" ]] ; then
	echo "Virtal machine to backup name is not set !!!"
	exit 1
fi
VMExists ${VM2BACKUP}
if [[ ${isVMFound} -ne 1 ]] ; then
	echo "Virtal machine named ${VM2BACKUP} doesn't exist !!!"
	exit 1
fi

# 1. utworzenie katalogu na kopie
mkdir -p ${BACKUP_DIR}

# 2. kopia pliku konfiguracyjnego maszyny
CONFIG_FILE=$(${VBOXCOMMAND} showvminfo ${VM2BACKUP} |grep "Config file:"| sed -e 's/Config file:[ ]*//')
VMROOTDIR=$(dirname ${CONFIG_FILE})
cp "${CONFIG_FILE}" "${BACKUP_DIR}/"

# 2.1 ustalenie nazw dysków wirtualnych maszyny
#     musi być ustalone przed zrobieniem snapshota
# wykrywa urządzenia IDE i SATA w opisie maszyny
#  parsuje i kopiuje wszystkie, które nie są Empty
#  IDE (1, 0): Empty
#  SATA (0, 0): /run/media/seweryn/ADATA_NH13/VM.new/snapshot_test_C7/snapshot_test_C7-disk1.vdi (UUID: 1b517908-b490-402a-9c0a-de73fd84c120)

# ghettoVBox string separator
gVSS="#10#13"
VDINAMES=""
IFS="$(printf '\n\t')"
for VDINAME in `${VBOXCOMMAND} showvminfo ${VM2BACKUP} |grep -e "^\(IDE\|SATA\)"|sed -e 's/^[^:]\+:[ ]*//'|sed -e 's/[ ]*(UUID.\+)//'` ; do
        if [[ "${VDINAME}" != "Empty" ]] ; then
		if [[ "${VDINAMES}" != "" ]] ; then
			VDINAMES="${VDINAMES}${gVSS}"
		fi
                VDINAMES="${VDINAMES}${VDINAME}"
        fi
done
unset IFS

# 3. wykonanie snapshota chodzącej uruchomionej maszyny
${VBOXCOMMAND} snapshot ${VM2BACKUP} take ${TEMP_SNAPSHOT_NAME}

# 4. kopia głównych dysków maszyny bez snapshota wg. sporzadzonej 
#    wcześniej listy

# to wymagałoby redefinicji IFS
#for VDINAME in $VDINAMES ; do
#		cp ${VDINAME} ${BACKUP_DIR}/ 
#done
#echo ${VDINAMES}
echo ${VDINAMES} | awk -v dir=${BACKUP_DIR} -F${gVSS} '{ for(i=1;i<=NF;i++){cmd="cp \047"$i"\047 \047"dir"\047"; system(cmd)}}'

# 5. scalenie i likwidacja migawki
${VBOXCOMMAND} snapshot ${VM2BACKUP} delete ${TEMP_SNAPSHOT_NAME}

