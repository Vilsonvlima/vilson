#!/bin/bash
# ==============================================================================
# SCRIPT DE CONFIGURAÇÃO DO CERTIFICADO ZSCALER
# ==============================================================================
# Versão: 1.0
# Descrição: Configura automaticamente o certificado Zscaler root CA na máquina
#            de um novo usuário, garantindo que o AWS CLI funcione corretamente
#            atrás do proxy Zscaler. Inclui verificação e login automático
#            na AWS com o perfil 'inter'.
# ==============================================================================

# --- CONFIGURAÇÃO ---
URL_CERTIFICADO="https://netops.bi.local/util/Zscaler_root_pki.crt"
CAMINHO_CERTIFICADO_LOCAL="$HOME/.aws/Zscaler_root_pki.crt"
EXPORT_LINE="export AWS_CA_BUNDLE=$HOME/.aws/Zscaler_root_pki.crt"
PERFIL_AWS="inter"

# --- Cores ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

echo ""
echo -e "${CYAN}============================================================${NC}"
echo -e "${CYAN}   CONFIGURAÇÃO DO CERTIFICADO ZSCALER - SETUP INICIAL      ${NC}"
echo -e "${CYAN}============================================================${NC}"
echo ""

# ==============================================================================
# PASSO 1: VERIFICAR DEPENDÊNCIAS
# ==============================================================================
echo -e "${CYAN}[1/5] Verificando dependências...${NC}"

if ! command -v curl &>/dev/null; then
    echo -e "${RED}ERRO: 'curl' não encontrado. Instale o curl e tente novamente.${NC}"
    exit 1
fi

if ! command -v aws &>/dev/null; then
    echo -e "${RED}ERRO: AWS CLI não encontrado. Instale o AWS CLI e tente novamente.${NC}"
    exit 1
else
    echo -e "${GREEN}  -> AWS CLI encontrado: $(aws --version 2>&1)${NC}"
fi

echo -e "${GREEN}  -> Dependências OK.${NC}"
echo ""

# ==============================================================================
# PASSO 2: DOWNLOAD DO CERTIFICADO
# ==============================================================================
echo -e "${CYAN}[2/5] Baixando certificado Zscaler...${NC}"
echo -e "  -> URL: ${YELLOW}$URL_CERTIFICADO${NC}"
echo -e "  -> Destino: ${YELLOW}$CAMINHO_CERTIFICADO_LOCAL${NC}"

# Criar diretório ~/.aws se não existir
mkdir -p "$(dirname "$CAMINHO_CERTIFICADO_LOCAL")"

# Verificar se o certificado já existe
if [ -f "$CAMINHO_CERTIFICADO_LOCAL" ]; then
    echo -e "${YELLOW}  -> Certificado já existe no destino.${NC}"
    read -p "     Deseja baixar novamente e sobrescrever? (s/N): " overwrite
    if [[ "$overwrite" =~ ^[sS]$ ]]; then
        if curl --fail -s -L "$URL_CERTIFICADO" -o "$CAMINHO_CERTIFICADO_LOCAL"; then
            echo -e "${GREEN}  -> Certificado atualizado com sucesso!${NC}"
        else
            echo -e "${RED}ERRO: Falha ao baixar o certificado. Verifique sua conexão.${NC}"
            exit 1
        fi
    else
        echo -e "${GREEN}  -> Mantendo certificado existente.${NC}"
    fi
else
    if curl --fail -s -L "$URL_CERTIFICADO" -o "$CAMINHO_CERTIFICADO_LOCAL"; then
        echo -e "${GREEN}  -> Certificado baixado com sucesso!${NC}"
    else
        echo -e "${RED}ERRO: Falha ao baixar o certificado. Verifique sua conexão.${NC}"
        exit 1
    fi
fi

# Validar se o arquivo é um certificado PEM válido
if ! grep -q "BEGIN CERTIFICATE" "$CAMINHO_CERTIFICADO_LOCAL" 2>/dev/null; then
    echo -e "${RED}ERRO: O arquivo baixado não parece ser um certificado PEM válido.${NC}"
    exit 1
fi

echo -e "${GREEN}  -> Certificado validado (formato PEM OK).${NC}"
echo ""

# ==============================================================================
# PASSO 3: PERSISTIR AWS_CA_BUNDLE NOS ARQUIVOS DE PERFIL
# ==============================================================================
echo -e "${CYAN}[3/5] Persistindo AWS_CA_BUNDLE nos arquivos de perfil...${NC}"

# --- ~/.zshrc (padrão macOS Catalina+) ---
if [ -f "$HOME/.zshrc" ] || [[ "$SHELL" == *"zsh"* ]]; then
    if grep -q "AWS_CA_BUNDLE" "$HOME/.zshrc" 2>/dev/null; then
        echo -e "${YELLOW}  -> ~/.zshrc: já contém AWS_CA_BUNDLE. Pulando.${NC}"
    else
        echo "$EXPORT_LINE" >> "$HOME/.zshrc"
        echo -e "${GREEN}  -> ~/.zshrc: AWS_CA_BUNDLE adicionado com sucesso.${NC}"
    fi
fi

# --- ~/.bash_profile ---
if [ -f "$HOME/.bash_profile" ] || [[ "$SHELL" == *"bash"* ]]; then
    if grep -q "AWS_CA_BUNDLE" "$HOME/.bash_profile" 2>/dev/null; then
        echo -e "${YELLOW}  -> ~/.bash_profile: já contém AWS_CA_BUNDLE. Pulando.${NC}"
    else
        echo "$EXPORT_LINE" >> "$HOME/.bash_profile"
        echo -e "${GREEN}  -> ~/.bash_profile: AWS_CA_BUNDLE adicionado com sucesso.${NC}"
    fi
fi

# --- ~/.bashrc (Linux) ---
if [ -f "$HOME/.bashrc" ]; then
    if grep -q "AWS_CA_BUNDLE" "$HOME/.bashrc" 2>/dev/null; then
        echo -e "${YELLOW}  -> ~/.bashrc: já contém AWS_CA_BUNDLE. Pulando.${NC}"
    else
        echo "$EXPORT_LINE" >> "$HOME/.bashrc"
        echo -e "${GREEN}  -> ~/.bashrc: AWS_CA_BUNDLE adicionado com sucesso.${NC}"
    fi
fi

# Aplicar na sessão atual
export AWS_CA_BUNDLE="$CAMINHO_CERTIFICADO_LOCAL"
echo -e "${GREEN}  -> AWS_CA_BUNDLE aplicado na sessão atual.${NC}"
echo ""

# ==============================================================================
# PASSO 4: VERIFICAÇÃO E LOGIN NA AWS
# ==============================================================================
echo -e "${CYAN}[4/5] Verificando sessão AWS (perfil: '${PERFIL_AWS}')...${NC}"

aws sts get-caller-identity --profile "$PERFIL_AWS" &>/dev/null

if [ $? -ne 0 ]; then
    echo -e "${YELLOW}  -> Sessão inativa ou expirada. Iniciando login SSO...${NC}"
    echo ""

    aws sso login --profile "$PERFIL_AWS"

    if [ $? -ne 0 ]; then
        echo -e "${RED}  -> ERRO: Falha no login com o perfil '${PERFIL_AWS}'.${NC}"
        echo -e "${YELLOW}  -> O certificado foi configurado corretamente, mas o login falhou.${NC}"
        echo -e "${YELLOW}  -> Tente manualmente: aws sso login --profile ${PERFIL_AWS}${NC}"
    else
        echo -e "${GREEN}  -> Login realizado com sucesso!${NC}"
    fi
else
    echo -e "${GREEN}  -> Sessão ativa e válida para o perfil '${PERFIL_AWS}'.${NC}"
fi
echo ""

# ==============================================================================
# PASSO 5: VALIDAÇÃO FINAL
# ==============================================================================
echo -e "${CYAN}[5/5] Validando configuração...${NC}"

# Verificar variável na sessão atual
if [ -n "$AWS_CA_BUNDLE" ]; then
    echo -e "${GREEN}  -> AWS_CA_BUNDLE: $AWS_CA_BUNDLE${NC}"
else
    echo -e "${RED}  -> ERRO: AWS_CA_BUNDLE não está definido na sessão atual.${NC}"
fi

# Verificar se o arquivo existe e tem conteúdo
if [ -s "$CAMINHO_CERTIFICADO_LOCAL" ]; then
    echo -e "${GREEN}  -> Certificado: OK (arquivo existe e não está vazio).${NC}"
else
    echo -e "${RED}  -> ERRO: Arquivo de certificado não encontrado ou está vazio.${NC}"
fi

# Verificar persistência nos arquivos de perfil
echo -e "${GREEN}  -> Persistência nos arquivos de perfil:${NC}"
for profile_file in "$HOME/.zshrc" "$HOME/.bash_profile" "$HOME/.bashrc"; do
    if [ -f "$profile_file" ]; then
        if grep -q "AWS_CA_BUNDLE" "$profile_file" 2>/dev/null; then
            echo -e "${GREEN}     ✔ $profile_file${NC}"
        else
            echo -e "${YELLOW}     ✘ $profile_file (não configurado)${NC}"
        fi
    fi
done

# ==============================================================================
# RESUMO FINAL
# ==============================================================================
echo ""
echo -e "${CYAN}============================================================${NC}"
echo -e "${GREEN}   SETUP CONCLUÍDO!${NC}"
echo -e "${CYAN}============================================================${NC}"
echo ""
echo -e "  Certificado : ${YELLOW}$CAMINHO_CERTIFICADO_LOCAL${NC}"
echo -e "  Variável    : ${YELLOW}AWS_CA_BUNDLE=$AWS_CA_BUNDLE${NC}"
echo -e "  Perfil AWS  : ${YELLOW}$PERFIL_AWS${NC}"
echo ""
echo -e "${CYAN}  PRÓXIMOS PASSOS:${NC}"
echo -e "  1. Recarregue seu terminal ou execute:"
echo -e "     ${YELLOW}source ~/.zshrc${NC}       (se usar zsh)"
echo -e "     ${YELLOW}source ~/.bash_profile${NC} (se usar bash)"
echo -e "  2. Para logar manualmente na AWS:"
echo -e "     ${YELLOW}aws sso login --profile ${PERFIL_AWS}${NC}"
echo ""
