#!/bin/zsh
echo "Deseja subir uma mudança específica ou todas?"
echo "Digite 1 para específica, 2 para todas"
read escolha
if [ "$escolha" = "1" ]; then
   echo "Digite o nome do arquivo que deseja subir (ex: arquivo.txt): "
   read arquivo
   git add "$arquivo"
elif [ "$escolha" = "2" ]; then
   git add .
else
   echo "Opção inválida!"
   exit 1
fi
echo "Digite a mensagem do commit:"
read mensagem
git commit -m "$mensagem"
git push origin main
