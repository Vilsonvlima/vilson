#!/bin/bash
# ==============================================================================
# SCRIPT HÍBRido PARA GESTÃO DE RECURSOS AWS (EC2, VPC, Subnets)
# ==============================================================================
# Versão: 15.3
# Desenvolvido por: Wesley de Jesus Alvarenga - wesley.jesus@inter.co
# MODIFICAÇÃO:
# - AÇÕES INTERATIVAS RESTAURADAS: Corrigido o fluxo para que o menu de
#   ações (SSH, Start/Stop) sempre apareça no modo interativo, mesmo ao
#   listar múltiplas regiões, restaurando a capacidade de agir nas instâncias.
# ==============================================================================
# --- CONFIGURAÇÃO ---
PERFIL_SSO_LOGIN="default"
URL_CERTIFICADO="https://netops.bi.local/util/Zscaler_root_pki.crt"
CAMINHO_CERTIFICADO_LOCAL="$HOME/.aws/Zscaler_root_pki.crt"
TEMP_PROFILE_NAME="temp-sso-session"
DEFAULT_KEY_DIR="$HOME/Documents/Repositorios/Keys/"

# --- CONFIGURAÇÃO DE LOG ---
LOG_DIR="$HOME/Documents/Projetos/Logs/aws_script_logs"
LOG_FILE_NAME="aws_query_results_$(date +'%Y-%m-%d_%H-%M-%S').log"
LOG_FILE_PATH="$LOG_DIR/$LOG_FILE_NAME"
# --- Cores ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'
# --- Funções ---
function show_usage() {
    echo "Uso Híbrido:"
    echo "  Modo Direto:     $0 [aws-profile] [aws-region]"
    echo "  Modo Interativo: $0"
    exit 1
}

# ==================== FUNÇÕES DE AÇÃO EC2 ====================
function connect_via_ssh() {
    local instance_line=$1
    local profile_to_use=$2
    local region=$3
    local instance_id=$(echo "$instance_line" | awk '{print $1}')
    local key_name=$(echo "$instance_line" | awk '{print $2}')
    local private_ip=$(echo "$instance_line" | awk '{print $5}')
    local platform=$(echo "$instance_line" | awk '{print $6}')
    local instance_name=$(echo "$instance_line" | awk '{print $7}')
    
    if [[ -z "$key_name" || "$key_name" == "None" ]]; then
        echo -e "${RED}ERRO: Instância não tem uma Key Pair associada. Não é possível conectar via SSH.${NC}"; return
    fi
    
    # Verificar tipo de instância Zscaler
    local is_zscaler_cc=false
    local is_zscaler_app=false
    local ssh_user=""
    local target_ip="$private_ip"
    
    # Verificar se é Zscaler Cloud Connector (padrão específico: ZSCALER-NEW-CC)
    if [[ "$instance_name" == *"ZSCALER-NEW-CC"* ]] || [[ "$instance_name" == *"zscaler-new-cc"* ]]; then
        is_zscaler_cc=true
        ssh_user="zsroot"
        
        # Buscar o IP da interface MGMT Interface
        echo -e "${CYAN}Detectado Zscaler Cloud Connector. Buscando IP da interface MGMT...${NC}"
        
        # Obter todas as interfaces da instância com suas descrições e IPs
        local interfaces_json=$(aws ec2 describe-network-interfaces \
            --filters "Name=attachment.instance-id,Values=$instance_id" \
            --query "NetworkInterfaces[].[Description, PrivateIpAddress]" \
            --profile "$profile_to_use" \
            --region "$region" \
            --output json 2>/dev/null)
        
        if [[ -n "$interfaces_json" ]]; then
            # Tentar encontrar interface com "MGMT Interface" na descrição
            local mgmt_ip=$(echo "$interfaces_json" | jq -r '.[] | select(.[0] | contains("MGMT Interface")) | .[1]' 2>/dev/null | head -1)
            
            if [[ -z "$mgmt_ip" || "$mgmt_ip" == "null" ]]; then
                # Tentar variações: MGMT, Management, mgmt
                mgmt_ip=$(echo "$interfaces_json" | jq -r '.[] | select(.[0] | test("MGMT|Management|mgmt"; "i")) | .[1]' 2>/dev/null | head -1)
            fi
            
            if [[ -n "$mgmt_ip" && "$mgmt_ip" != "null" ]]; then
                target_ip="$mgmt_ip"
                echo -e "${GREEN}IP da interface MGMT encontrado: ${target_ip}${NC}"
            else
                echo -e "${YELLOW}AVISO: Interface MGMT não encontrada. Listando todas as interfaces disponíveis:${NC}"
                echo "$interfaces_json" | jq -r '.[] | "  - \(.[0]): \(.[1])"' 2>/dev/null
                echo -e "${YELLOW}Usando IP privado padrão: ${private_ip}${NC}"
            fi
        else
            echo -e "${YELLOW}AVISO: Não foi possível listar interfaces. Usando IP privado padrão.${NC}"
        fi
    # Verificar se é Zscaler App Connector (ZPA)
    elif [[ "$instance_name" == *"ZPA-CONNECTOR"* ]] || [[ "$instance_name" == *"ZPA-APP-CONNECTOR"* ]] || [[ "$instance_name" == *"SIPA"* ]] || [[ "$instance_name" == *"ZPA"* ]]; then
        is_zscaler_app=true
        ssh_user="admin"
        echo -e "${CYAN}Detectado Zscaler App Connector (ZPA). Usando usuário 'admin' e IP privado padrão.${NC}"
    else
        # Lógica padrão para outras instâncias
        case "$platform" in
            *Amazon*|*amzn*) ssh_user="ec2-user" ;;
            *Ubuntu*) ssh_user="ubuntu" ;;
            *CentOS*) ssh_user="centos" ;;
            *RHEL*) ssh_user="ec2-user" ;;
            *Debian*) ssh_user="admin" ;;
            *) ssh_user="ec2-user" ;;
        esac
    fi
    
    if [[ -z "$target_ip" ]]; then
        echo -e "${RED}ERRO: Não foi possível determinar um IP válido para conexão. Abortando.${NC}"; return
    fi
    
    local suggested_key_path="${DEFAULT_KEY_DIR}${key_name}.pem"
    echo -e "\n--- Configurando Conexão SSH (via IP Privado) ---"
    if [ "$is_zscaler_cc" = true ]; then
        echo -e "${CYAN}Tipo de instância: Zscaler Cloud Connector${NC}"
    elif [ "$is_zscaler_app" = true ]; then
        echo -e "${CYAN}Tipo de instância: Zscaler App Connector (ZPA)${NC}"
    fi
    echo -e "Usuário SSH detectado automaticamente: ${YELLOW}${ssh_user}${NC}"
    read -e -p "Caminho para a chave .pem [sugerido: ${YELLOW}${suggested_key_path}${NC}]: " key_path
    key_path=${key_path:-$suggested_key_path}; key_path="${key_path/#\~/$HOME}"
    if [ ! -f "$key_path" ]; then
        echo -e "${RED}ERRO: Arquivo de chave não encontrado em '${key_path}'. Abortando.${NC}"; return
    fi
    echo -e "\n${CYAN}Tentando conectar...${NC}"
    echo -e "Comando: ${YELLOW}ssh -i \"$key_path\" ${ssh_user}@${target_ip}${NC}"
    ssh -i "$key_path" "${ssh_user}@${target_ip}"
}

function manage_instance_state() {
    local instance_id=$1 profile_to_use=$2 region=$3
    echo -e "\nQual ação deseja executar em ${CYAN}$instance_id${NC}?"
    local original_ps3=$PS3; PS3="Escolha a ação: ";
    select action in "Start" "Stop" "Reboot" "Cancelar"; do
        case "$action" in
            "Start"|"Stop"|"Reboot")
                read -p "Tem certeza que deseja executar a ação '$action' em $instance_id? (s/N): " confirm
                if [[ "$confirm" =~ ^[sS]$ ]]; then
                    local command_action=$(echo "$action" | tr '[:upper:]' '[:lower:]')
                    echo -e "${YELLOW}Executando '${command_action}' na instância ${instance_id}...${NC}"
                    aws ec2 "${command_action}-instances" --instance-ids "$instance_id" --profile "$profile_to_use" --region "$region"
                else echo "Ação cancelada."; fi
                break ;;
            "Cancelar") echo "Operação cancelada."; break;;
            *) echo "Opção inválida.";;
        esac
    done
    PS3=$original_ps3
}

function prompt_for_instance_actions() {
    local instance_data=$1 profile_to_use=$2 region=$3
    if [ -z "$instance_data" ]; then return; fi
    while true; do
        echo -e "\n${CYAN}O que deseja fazer?${NC}"
        local original_ps3=$PS3; PS3="Escolha uma opção: ";
        select action_choice in "Conectar via SSH" "Gerenciar Estado (Start/Stop/Reboot)" "Continuar (próxima região/voltar)"; do
            case "$action_choice" in
                "Conectar via SSH"|"Gerenciar Estado (Start/Stop/Reboot)")
                    echo -e "\nEscolha a instância para a ação '${action_choice}':"
                    declare -a INSTANCE_OPTIONS=()
                    while IFS= read -r line; do if [[ -n "$line" ]]; then INSTANCE_OPTIONS+=("$line"); fi; done < <(echo "$instance_data" | awk -F'\t' '{printf "%s (%s)\n", $1, $7}')
                    INSTANCE_OPTIONS+=("Cancelar")
                    select target in "${INSTANCE_OPTIONS[@]}"; do
                        if [ "$target" == "Cancelar" ]; then break; fi
                        if [ -n "$target" ]; then
                            local instance_id=$(echo "$target" | awk '{print $1}')
                            local selected_instance_line=$(echo "$instance_data" | grep "^$instance_id")
                            if [ "$action_choice" == "Conectar via SSH" ]; then connect_via_ssh "$selected_instance_line" "$profile_to_use" "$region"; fi
                            if [ "$action_choice" == "Gerenciar Estado (Start/Stop/Reboot)" ]; then manage_instance_state "$instance_id" "$profile_to_use" "$region"; fi
                            break
                        else echo "Opção inválida."; fi
                    done
                    # Após a ação, volta a mostrar o menu de ações para a mesma região
                    break ;;
                "Continuar (próxima região/voltar)") PS3=$original_ps3; return ;;
                *) echo "Opção inválida.";;
            esac
        done
        PS3=$original_ps3
    done
}

function get_instances_in_region() {
    local region=$1 name_filter=$2 profile_to_use=$3 show_actions_menu=${4:-true}
    local filter_arg=""
    if [ -z "$region" ] || [ -z "$profile_to_use" ]; then return; fi
    echo -e "\n  -> Buscando instâncias EC2 na região ${GREEN}$region${NC}"
    if [ -n "$name_filter" ]; then echo "     (Filtro: '*$name_filter*')"; filter_arg="--filters Name=tag:Name,Values=*$name_filter*"; fi
    local INSTANCES=$(aws ec2 describe-instances --profile "$profile_to_use" --region "$region" $filter_arg \
        --query "Reservations[].Instances[].[InstanceId, KeyName, VpcId, State.Name, PrivateIpAddress, PlatformDetails, Tags[?Key=='Name'].Value | [0]]" --output text 2>/dev/null)
    local screen_output="" log_output="" context_header="--[ Perfil: $profile_to_use | Região: $region | $(date +'%Y-%m-%d %H:%M:%S') | EC2 ]--"
    if [ $? -ne 0 ]; then
        screen_output="  ${RED}FALHA AO BUSCAR EC2! Verifique as credenciais/permissões.${NC}"
        log_output="$context_header\nFALHA AO BUSCAR EC2! Verifique as credenciais/permissões."
    elif [ -n "$INSTANCES" ]; then
        local header_line="  ----------------------------------------------------------------------------------------------------------------------------"
        local header_cols_screen="  ID da Instância\t\tVPC ID\t\t\tEstado\t\tIP Privado\t\tPlataforma (SO)\t\tNome"
        local header_cols_log="  ID da Instância          VPC ID             Estado       IP Privado       Plataforma (SO)            Nome"
        local formatted_instances_screen=$(echo "$INSTANCES" | awk -F'\t' 'BEGIN {OFS="\t"} {
            printf "  %-22s\t%-22s\t%-18s\t%-15s\t%-25s\t%s\n", $1, $3, "@"$4"@", $5, $6, $7
        }' | sed -e "s/@running@/${GREEN}running${NC}/g" \
                 -e "s/@stopped@/${RED}stopped${NC}/g" \
                 -e "s/@pending@/${YELLOW}pending${NC}/g" \
                 -e "s/@shutting-down@/${YELLOW}shutting-down${NC}/g" \
                 -e "s/@terminating@/${YELLOW}terminating${NC}/g")
        local formatted_instances_log=$(echo "$INSTANCES" | awk -F'\t' '{printf "  %-24s %-18s %-12s %-16s %-26s %s\n", $1, $3, $4, $5, $6, $7}')
        screen_output="$header_line\n$header_cols_screen\n$header_line\n$formatted_instances_screen\n$header_line"
        log_output="$context_header\n$header_line\n$header_cols_log\n$header_line\n$formatted_instances_log\n$header_line"
    else
        screen_output="  Nenhuma instância EC2 encontrada com os critérios definidos nesta região."
        log_output="$context_header\nNenhuma instância EC2 encontrada com os critérios definidos nesta região."
    fi
    echo -e "$screen_output"; echo -e "$log_output\n" >> "$LOG_FILE_PATH"
    if [ "$show_actions_menu" = true ]; then
        prompt_for_instance_actions "$INSTANCES" "$profile_to_use" "$region"
    fi
}

# ==================== FUNÇÕES PARA VPC E SUBNETS ====================
function get_subnets_for_vpc() {
    local vpc_id=$1 region=$2 profile_to_use=$3
    echo -e "\n  -> Buscando Subnets para a VPC ${CYAN}$vpc_id${NC} na região ${GREEN}$region${NC}"
    local SUBNETS=$(aws ec2 describe-subnets --profile "$profile_to_use" --region "$region" \
        --filters "Name=vpc-id,Values=$vpc_id" \
        --query "Subnets[].[SubnetId, CidrBlock, AvailabilityZone, AvailableIpAddressCount, Tags[?Key=='Name'].Value | [0]]" \
        --output text 2>/dev/null)
    local screen_output="" log_output="" context_header="--[ Perfil: $profile_to_use | Região: $region | $(date +'%Y-%m-%d %H:%M:%S') | Subnets ]--"
    if [ $? -ne 0 ]; then
        screen_output="  ${RED}FALHA AO BUSCAR Subnets! Verifique as credenciais/permissões.${NC}"
        log_output="$context_header\nFALHA AO BUSCAR Subnets! Verifique as credenciais/permissões."
    elif [ -n "$SUBNETS" ]; then
        local header_line="  -------------------------------------------------------------------------------------------------------------------"
        local header_cols_screen="  ID da Subnet\t\t\tCIDR Block\t\tZona de Disp.\t\tIPs Disponíveis\t\tNome"
        local header_cols_log="  ID da Subnet                 CIDR Block         Zona de Disp.  IPs Disponíveis  Nome"
        local formatted_subnets_screen=$(echo "$SUBNETS" | awk -F'\t' 'BEGIN {OFS="\t"} {printf "  %-28s\t%-18s\t%-18s\t%-15s\t%s\n", $1, $2, $3, $4, $5}')
        local formatted_subnets_log=$(echo "$SUBNETS" | awk -F'\t' '{printf "  %-28s %-18s %-18s %-15s %s\n", $1, $2, $3, $4, $5}')
        screen_output="$header_line\n$header_cols_screen\n$header_line\n$formatted_subnets_screen\n$header_line"
        log_output="$context_header\n$header_line\n$header_cols_log\n$header_line\n$formatted_subnets_log\n$header_line"
    else
        screen_output="  Nenhuma Subnet encontrada para esta VPC."
        log_output="$context_header\nNenhuma Subnet encontrada para esta VPC."
    fi
    echo -e "$screen_output"; echo -e "$log_output\n" >> "$LOG_FILE_PATH"
}

function prompt_for_vpc_actions() {
    local vpc_data=$1 profile_to_use=$2 region=$3
    if [ -z "$vpc_data" ]; then return; fi
    while true; do
        echo -e "\n${CYAN}O que deseja fazer com as VPCs listadas?${NC}"
        local original_ps3=$PS3; PS3="Escolha uma opção: ";
        select action_choice in "Listar Subnets de uma VPC" "Continuar (próxima região/voltar)"; do
            case "$action_choice" in
                "Listar Subnets de uma VPC")
                    echo -e "\nEscolha a VPC para listar suas subnets:"
                    declare -a VPC_OPTIONS=()
                    while IFS= read -r line; do if [[ -n "$line" ]]; then VPC_OPTIONS+=("$line"); fi; done < <(echo "$vpc_data" | awk -F'\t' '{printf "%s (%s)\n", $1, $5}')
                    VPC_OPTIONS+=("Cancelar")
                    select target in "${VPC_OPTIONS[@]}"; do
                        if [ "$target" == "Cancelar" ]; then break; fi
                        if [ -n "$target" ]; then
                            local vpc_id=$(echo "$target" | awk '{print $1}')
                            get_subnets_for_vpc "$vpc_id" "$region" "$profile_to_use"
                            break
                        else echo "Opção inválida."; fi
                    done
                    break ;;
                "Continuar (próxima região/voltar)") PS3=$original_ps3; return ;;
                *) echo "Opção inválida.";;
            esac
        done
        PS3=$original_ps3
    done
}

function get_vpcs_in_region() {
    local region=$1 profile_to_use=$2 show_actions_menu=${3:-true}
    if [ -z "$region" ] || [ -z "$profile_to_use" ]; then return; fi
    echo -e "\n  -> Buscando VPCs na região ${GREEN}$region${NC}"
    local VPCS=$(aws ec2 describe-vpcs --profile "$profile_to_use" --region "$region" \
        --query "Vpcs[].[VpcId, CidrBlock, IsDefault, State, Tags[?Key=='Name'].Value | [0]]" \
        --output text 2>/dev/null)
    local screen_output="" log_output="" context_header="--[ Perfil: $profile_to_use | Região: $region | $(date +'%Y-%m-%d %H:%M:%S') | VPC ]--"
    if [ $? -ne 0 ]; then
        screen_output="  ${RED}FALHA AO BUSCAR VPCs! Verifique as credenciais/permissões.${NC}"
        log_output="$context_header\nFALHA AO BUSCAR VPCs! Verifique as credenciais/permissões."
    elif [ -n "$VPCS" ]; then
        local header_line="  --------------------------------------------------------------------------------------------"
        local header_cols_screen="  VPC ID\t\t\tCIDR Block\t\tPadrão?\t\tEstado\t\tNome"
        local header_cols_log="  VPC ID               CIDR Block         Padrão?  Estado     Nome"
        local formatted_vpcs_screen=$(echo "$VPCS" | awk -F'\t' -v G="$GREEN" -v Y="$YELLOW" -v NC="$NC" 'BEGIN {OFS="\t"} { state=$4; is_default = ($3 == "true") ? Y "Sim" NC : "Não"; state_color = (state == "available") ? G state NC : Y state NC; printf "  %-22s\t%-18s\t%-10s\t%-18s\t%s\n", $1, $2, is_default, state_color, $5 }')
        local formatted_vpcs_log=$(echo "$VPCS" | awk -F'\t' '{printf "  %-22s %-18s %-8s %-10s %s\n", $1, $2, $3, $4, $5}')
        screen_output="$header_line\n$header_cols_screen\n$header_line\n$formatted_vpcs_screen\n$header_line"
        log_output="$context_header\n$header_line\n$header_cols_log\n$header_line\n$formatted_vpcs_log\n$header_line"
    else
        screen_output="  Nenhuma VPC encontrada nesta região."
        log_output="$context_header\nNenhuma VPC encontrada nesta região."
    fi
    echo -e "$screen_output"; echo -e "$log_output\n" >> "$LOG_FILE_PATH"
    if [ "$show_actions_menu" = true ]; then
        prompt_for_vpc_actions "$VPCS" "$profile_to_use" "$region"
    fi
}

# ==================== FLUXOS DE LISTAGEM ====================
function run_ec2_listing_flow() {
    local profile_for_listing=$1
    echo -e "\nDigite um termo para filtrar o NOME da instância (ex: TSHOOT, WEB)."
    read -p "Deixe em branco para ver todas: " NAME_FILTER
    local regions=("us-east-1 (Virginia)" "sa-east-1 (São Paulo)" "us-east-2 (Ohio)")
    declare -a REGION_OPTIONS=("${regions[@]}")
    REGION_OPTIONS+=("Todas as 3 Regiões")
    REGION_OPTIONS+=("Informar Outra Região Manualmente")
    REGION_OPTIONS+=("Voltar")
    echo -e "\nEscolha a região para verificar INSTÂNCIAS EC2:"
    select REGION_CHOICE in "${REGION_OPTIONS[@]}"; do
        if [ -n "$REGION_CHOICE" ]; then break; else echo "Opção inválida."; fi
    done
    case "$REGION_CHOICE" in
        "Todas as 3 Regiões")
            for region_item in "${regions[@]}"; do
                # === CORREÇÃO AQUI: Passa 'true' para SEMPRE mostrar o menu de ações no fluxo interativo ===
                get_instances_in_region "$(echo "$region_item" | awk '{print $1}')" "$NAME_FILTER" "$profile_for_listing" true
            done ;;
        "Informar Outra Região Manualmente") 
            read -p "Informe o código da região (ex: us-west-2): " manual_region
            get_instances_in_region "$manual_region" "$NAME_FILTER" "$profile_for_listing" true ;;
        "Voltar") return ;; 
        *) get_instances_in_region "$(echo "$REGION_CHOICE" | awk '{print $1}')" "$NAME_FILTER" "$profile_for_listing" true ;;
    esac
}

function run_vpc_listing_flow() {
    local profile_for_listing=$1
    local regions=("us-east-1 (Virginia)" "sa-east-1 (São Paulo)" "us-east-2 (Ohio)")
    declare -a REGION_OPTIONS=("${regions[@]}")
    REGION_OPTIONS+=("Todas as 3 Regiões")
    REGION_OPTIONS+=("Informar Outra Região Manualmente")
    REGION_OPTIONS+=("Voltar")
    echo -e "\nEscolha a região para verificar VPCs:"
    select REGION_CHOICE in "${REGION_OPTIONS[@]}"; do
        if [ -n "$REGION_CHOICE" ]; then break; else echo "Opção inválida."; fi
    done
    case "$REGION_CHOICE" in
        "Todas as 3 Regiões")
            for region_item in "${regions[@]}"; do
                # O menu de ações de VPC também deve aparecer
                get_vpcs_in_region "$(echo "$region_item" | awk '{print $1}')" "$profile_for_listing" true
            done ;;
        "Informar Outra Região Manualmente")
            read -p "Informe o código da região (ex: us-west-2): " manual_region
            get_vpcs_in_region "$manual_region" "$profile_for_listing" true ;;
        "Voltar") return ;;
        *) get_vpcs_in_region "$(echo "$REGION_CHOICE" | awk '{print $1}')" "$profile_for_listing" true ;;
    esac
}

# ==================== FUNÇÕES DE LISTAGEM COMPLETA ====================
function run_bulk_listing_flow() {
    echo -e "\n${CYAN}=== LISTAGEM COMPLETA (TODOS OS PERFIS) ===${NC}"
    PS3="Escolha o tipo de listagem: "
    select list_type in "Listagem de Instâncias EC2" "Listagem de VPCs" "Voltar"; do
        case "$list_type" in
            "Listagem de Instâncias EC2")
                echo -e "\n${CYAN}--- INICIANDO LISTAGEM EC2 EM TODOS OS PERFIS ---${NC}"
                read -p "Digite um termo para filtrar o nome da instância (deixe em branco para todas): " NAME_FILTER
                ALL_PROFILES=($(aws configure list-profiles))
                if [ ${#ALL_PROFILES[@]} -eq 0 ]; then echo -e "${RED}Nenhum perfil encontrado.${NC}"; return; fi
                REGIONS_TO_CHECK=("us-east-1" "sa-east-1" "us-east-2")
                for profile in "${ALL_PROFILES[@]}"; do
                    echo -e "\n==================== Verificando Perfil: ${YELLOW}${profile}${NC} ===================="
                    for region in "${REGIONS_TO_CHECK[@]}"; do
                        get_instances_in_region "$region" "$NAME_FILTER" "$profile" false
                    done
                done
                echo -e "\n${GREEN}--- LISTAGEM EC2 COMPLETA ---${NC}"
                break ;;
            "Listagem de VPCs")
                echo -e "\n${CYAN}--- INICIANDO LISTAGEM VPC EM TODOS OS PERFIS ---${NC}"
                ALL_PROFILES=($(aws configure list-profiles))
                if [ ${#ALL_PROFILES[@]} -eq 0 ]; then echo -e "${RED}Nenhum perfil encontrado.${NC}"; return; fi
                REGIONS_TO_CHECK=("us-east-1" "sa-east-1" "us-east-2")
                for profile in "${ALL_PROFILES[@]}"; do
                    echo -e "\n==================== Verificando Perfil: ${YELLOW}${profile}${NC} ===================="
                    for region in "${REGIONS_TO_CHECK[@]}"; do
                        get_vpcs_in_region "$region" "$profile" false
                    done
                done
                echo -e "\n${GREEN}--- LISTAGEM VPC COMPLETA ---${NC}"
                break ;;
            "Voltar") return ;;
            *) echo "Opção inválida." ;;
        esac
    done
}

# ==============================================================================
# INÍCIO DA EXECUÇÃO
# ==============================================================================
mkdir -p "$LOG_DIR"
echo -e "${CYAN}Resultados das consultas serão salvos em:${NC} ${YELLOW}$LOG_FILE_PATH${NC}"
echo "------------------------------------------------------------------"
echo "Verificando configuração do certificado (AWS_CA_BUNDLE)..."
if [ -z "$AWS_CA_BUNDLE" ]; then
    mkdir -p "$(dirname "$CAMINHO_CERTIFICADO_LOCAL")"; if curl --fail -s -L "$URL_CERTIFICADO" -o "$CAMINHO_CERTIFICADO_LOCAL"; then
    export AWS_CA_BUNDLE="$CAMINHO_CERTIFICADO_LOCAL"; echo -e "${GREEN}Configurado.${NC}"; else
    echo -e "${RED}ERRO: Falha ao baixar o certificado. Saindo.${NC}"; exit 1; fi
else echo -e "${GREEN}Já configurado.${NC}"; fi; echo "------------------------------------------------------------------"

if [ "$#" -ge 2 ]; then
    PROFILE_ARG=$1; REGION_ARG=$2; echo -e "${CYAN}Executando em Modo Direto (apenas EC2)...${NC}"; echo -e "  - Perfil AWS: ${YELLOW}$PROFILE_ARG${NC}"; echo -e "  - Região AWS: ${YELLOW}$REGION_ARG${NC}"; echo -e "\nDigite um termo para filtrar o nome da instância."; read -p "Deixe em branco para ver todas: " NAME_FILTER; get_instances_in_region "$REGION_ARG" "$NAME_FILTER" "$PROFILE_ARG"; exit 0
elif [ "$#" -gt 0 ]; then echo -e "${RED}Erro: Você deve fornecer o perfil E a região, ou nenhum argumento.${NC}"; show_usage; fi

echo -e "${CYAN}Iniciando em Modo Interativo...${NC}"
while true; do
    PS3=$'\n'"Escolha uma opção de autenticação: "
    declare -a AUTH_MENU_OPTIONS=("Listagem Completa (Todos os Perfis)" "Iniciar sessão com AWS SSO (Fluxo Guiado)")
    EXISTING_PROFILES=($(aws configure list-profiles))
    if [ $? -eq 0 ] && [ ${#EXISTING_PROFILES[@]} -gt 0 ]; then
        for profile in "${EXISTING_PROFILES[@]}"; do AUTH_MENU_OPTIONS+=("$profile"); done
    fi
    AUTH_MENU_OPTIONS+=("Sair")
    
    echo -e "\n=============== MENU DE AUTENTICAÇÃO ==============="
    select AUTH_CHOICE in "${AUTH_MENU_OPTIONS[@]}"; do
        if [[ -n "$AUTH_CHOICE" ]]; then break; else echo -e "${RED}Opção inválida.${NC}"; fi
    done
    
    ACTIVE_PROFILE=""
    case "$AUTH_CHOICE" in
        "Sair") echo "Saindo. Até logo!"; exit 0;;
        "Listagem Completa (Todos os Perfis)")
            run_bulk_listing_flow
            continue ;;
        "Iniciar sessão com AWS SSO (Fluxo Guiado)")
            aws sso login --profile "$PERFIL_SSO_LOGIN"; if [ $? -ne 0 ]; then echo -e "${RED}Falha no login do SSO.${NC}"; continue; fi
            cached_sso_file=$(ls -t ~/.aws/sso/cache/*.json 2>/dev/null | head -1)
            ACCESS_TOKEN=$(jq -r .accessToken "$cached_sso_file")
            ACCOUNT_LIST_JSON=$(aws sso list-accounts --profile "$PERFIL_SSO_LOGIN" --access-token "$ACCESS_TOKEN" --query "accountList[].{id:accountId, name:accountName}" --output json)
            if [ $? -ne 0 ] || [ -z "$ACCOUNT_LIST_JSON" ]; then echo -e "${RED}Não foi possível listar contas.${NC}"; continue; fi
            declare -a ACCOUNT_OPTIONS=(); while IFS= read -r line; do ACCOUNT_OPTIONS+=("$line"); done < <(echo "$ACCOUNT_LIST_JSON" | jq -r '.[] | "\(.id) (\(.name))"'); ACCOUNT_OPTIONS+=("Voltar")
            echo -e "\nEscolha uma conta:"; select ACCOUNT_CHOICE in "${ACCOUNT_OPTIONS[@]}"; do
                if [[ "$ACCOUNT_CHOICE" == "Voltar" ]]; then break; fi
                if [[ -n "$ACCOUNT_CHOICE" ]]; then
                    SELECTED_ACCOUNT_ID=$(echo "$ACCOUNT_CHOICE" | awk '{print $1}')
                    ROLE_LIST_JSON=$(aws sso list-account-roles --profile "$PERFIL_SSO_LOGIN" --account-id "$SELECTED_ACCOUNT_ID" --access-token "$ACCESS_TOKEN" --query "roleList[].roleName" --output json)
                    declare -a ROLE_OPTIONS=(); while IFS= read -r line; do ROLE_OPTIONS+=("$line"); done < <(echo "$ROLE_LIST_JSON" | jq -r '.[]'); ROLE_OPTIONS+=("Voltar")
                    echo -e "\nEscolha a role para a conta ${YELLOW}$SELECTED_ACCOUNT_ID${NC}:"; select SELECTED_ROLE_NAME in "${ROLE_OPTIONS[@]}"; do
                        if [[ "$SELECTED_ROLE_NAME" == "Voltar" ]]; then break; fi
                        if [ -n "$SELECTED_ROLE_NAME" ]; then
                            CREDENTIALS_JSON=$(aws sso get-role-credentials --profile "$PERFIL_SSO_LOGIN" --account-id "$SELECTED_ACCOUNT_ID" --role-name "$SELECTED_ROLE_NAME" --access-token "$ACCESS_TOKEN" --output json)
                            if [ $? -ne 0 ]; then echo -e "${RED}Não foi possível obter credenciais.${NC}"; break; fi
                            AWS_ACCESS_KEY_ID=$(echo "$CREDENTIALS_JSON" | jq -r '.roleCredentials.accessKeyId'); AWS_SECRET_ACCESS_KEY=$(echo "$CREDENTIALS_JSON" | jq -r '.roleCredentials.secretAccessKey'); AWS_SESSION_TOKEN=$(echo "$CREDENTIALS_JSON" | jq -r '.roleCredentials.sessionToken')
                            aws configure set aws_access_key_id "$AWS_ACCESS_KEY_ID" --profile "$TEMP_PROFILE_NAME" > /dev/null
                            aws configure set aws_secret_access_key "$AWS_SECRET_ACCESS_KEY" --profile "$TEMP_PROFILE_NAME" > /dev/null
                            aws configure set aws_session_token "$AWS_SESSION_TOKEN" --profile "$TEMP_PROFILE_NAME" > /dev/null
                            echo -e "${GREEN}Perfil temporário '${TEMP_PROFILE_NAME}' configurado!${NC}"; ACTIVE_PROFILE="$TEMP_PROFILE_NAME"; break 2
                        fi
                    done
                fi
            done
            if [ -z "$ACTIVE_PROFILE" ]; then continue; fi ;;
        *) ACTIVE_PROFILE=$AUTH_CHOICE ;;
    esac

    if [ -n "$ACTIVE_PROFILE" ]; then
        while true; do
            echo -e "\n=============== MENU PRINCIPAL (Perfil: ${YELLOW}${ACTIVE_PROFILE}${NC}) ==============="
            PS3="O que deseja fazer? "
            select ACTION_CHOICE in "Listar Instâncias EC2" "Listar VPCs" "Trocar Perfil / Sair"; do
                case "$ACTION_CHOICE" in
                    "Listar Instâncias EC2") run_ec2_listing_flow "$ACTIVE_PROFILE"; break ;;
                    "Listar VPCs") run_vpc_listing_flow "$ACTIVE_PROFILE"; break ;;
                    "Trocar Perfil / Sair") break 2 ;;
                    *) echo "Opção inválida." ;;
                esac
            done
        done
    fi
    echo "------------------------------------------------------------------"
done