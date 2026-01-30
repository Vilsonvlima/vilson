#!/bin/zsh
echo "Deseja subir uma mudança específica ou todas?"
echo "Digite 1 para específica, 2 para todas"
read escolha

if [ "$escolha" = "1" ]; then
   echo "Arquivos modificados/novos disponíveis:"
   echo "----------------------------------------"
   
   # Cria arquivo temporário com os arquivos modificados
   git status --porcelain > /tmp/git_status.tmp
   
   # Verifica se existem arquivos modificados
   if [ ! -s /tmp/git_status.tmp ]; then
       echo "Nenhum arquivo modificado encontrado!"
       rm -f /tmp/git_status.tmp
       exit 1
   fi
   
   # Lista os arquivos numerados
   contador=1
   while IFS= read -r linha; do
       status=$(echo "$linha" | awk '{print $1}')
       arquivo=$(echo "$linha" | awk '{print $2}')
       echo "$contador) $arquivo [$status]"
       contador=$((contador + 1))
   done < /tmp/git_status.tmp
   
   total_arquivos=$((contador - 1))
   
   echo "----------------------------------------"
   echo "Digite o número do arquivo que deseja subir:"
   read numero
   
   # Valida se o número está no range correto
   if [[ "$numero" =~ ^[0-9]+$ ]] && [ "$numero" -ge 1 ] && [ "$numero" -le $total_arquivos ]; then
       arquivo_selecionado=$(sed -n "${numero}p" /tmp/git_status.tmp | awk '{print $2}')
       git add "$arquivo_selecionado"
       echo "Arquivo '$arquivo_selecionado' adicionado com sucesso!"
   else
       echo "Número inválido! Digite um número entre 1 e $total_arquivos"
       rm -f /tmp/git_status.tmp
       exit 1
   fi
   
   # Remove arquivo temporário
   rm -f /tmp/git_status.tmp
   
elif [ "$escolha" = "2" ]; then
   echo "Adicionando todos os arquivos modificados..."
   git add .
else
   echo "Opção inválida!"
   exit 1
fi

echo "Digite a mensagem do commit:"
read mensagem
git commit -m "$mensagem"
git push origin main
