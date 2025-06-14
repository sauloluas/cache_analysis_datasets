#!/bin/bash

# Configurações fixas
TAMANHO_CACHE=2048
BLOCK_SIZES=(32 64 128)
ASSOCIATIVIDADES=(1 2 4 8 16 0)  # 0 = Fully Associative

# Nome do arquivo de configuração base
CFG_BASE="cache.cfg"
DIR_RESULTADOS="resultados_cacti"
LOG_ERROS="erros_cacti.log"

# Criar diretório para resultados
mkdir -p "$DIR_RESULTADOS"

# Função aprimorada de validação
verificar_config() {
    local block_size=$1
    local associativity=$2
    
    # 1. Verificar se o tamanho do bloco é válido
    if ((block_size > TAMANHO_CACHE)); then
        return 1  # Bloco maior que a cache
    fi
    
    # 2. Calcular número de blocos e conjuntos
    local num_blocos=$((TAMANHO_CACHE / block_size))
    local num_conjuntos=$((associativity == 0 ? 1 : num_blocos / associativity))
    
    # 3. Verificar se a divisão é exata
    if ((associativity > 0 && num_blocos % associativity != 0)); then
        return 1  # Número não divisível
    fi
    
    # 4. Verificar limites mínimos
    if ((num_conjuntos < 4 && associativity != 0)); then
        return 1  # Muito poucos conjuntos
    fi
    
    # 5. Verificar configurações problemáticas conhecidas
    if [[ $associativity -eq 0 && $block_size -gt 64 ]]; then
        return 1  # Totalmente associativa com blocos grandes
    fi
    
    if [[ $block_size -eq 128 && $associativity -ge 8 ]]; then
        return 1  # Blocos grandes com alta associatividade
    fi
    
    return 0  # Configuração válida
}

# Loop principal
for block_size in "${BLOCK_SIZES[@]}"; do
    for associativity in "${ASSOCIATIVIDADES[@]}"; do
        # Verificar se a configuração é válida
        if ! verificar_config "$block_size" "$associativity"; then
            echo "Configuração ignorada (inválida): Size=$TAMANHO_CACHE Block=$block_size Assoc=$associativity" | tee -a "$LOG_ERROS"
            
            # Criar arquivo de resultado marcando como inválido
            saida="${DIR_RESULTADOS}/resultado_${TAMANHO_CACHE}_${block_size}_${associativity}.out"
            echo "CONFIGURAÇÃO INVÁLIDA PRÉ-DETECTADA" > "$saida"
            echo "Motivo:" >> "$saida"
            
            # Adicionar motivo específico
            if ((block_size > TAMANHO_CACHE)); then
                echo "- Tamanho do bloco ($block_size) maior que o tamanho da cache ($TAMANHO_CACHE)" >> "$saida"
            fi
            
            local num_blocos=$((TAMANHO_CACHE / block_size))
            if ((associativity > 0 && num_blocos % associativity != 0)); then
                echo "- Número de blocos ($num_blocos) não é divisível pela associatividade ($associativity)" >> "$saida"
            fi
            
            local num_conjuntos=$((associativity == 0 ? 1 : num_blocos / associativity))
            if ((num_conjuntos < 4 && associativity != 0)); then
                echo "- Número de conjuntos ($num_conjuntos) menor que 4" >> "$saida"
            fi
            
            if [[ $associativity -eq 0 && $block_size -gt 64 ]]; then
                echo "- Configuração totalmente associativa com bloco maior que 64 bytes" >> "$saida"
            fi
            
            if [[ $block_size -eq 128 && $associativity -ge 8 ]]; then
                echo "- Blocos de 128 bytes com associatividade 8 ou maior" >> "$saida"
            fi
            
            continue
        fi
        
        # Gerar nome do arquivo de configuração
        cfg_novo="${DIR_RESULTADOS}/cache_${TAMANHO_CACHE}_${block_size}_${associativity}.cfg"
        
        # Gerar novo arquivo de configuração
        sed -e "s/^-size (bytes) .*$/-size (bytes) $TAMANHO_CACHE/" \
            -e "s/^-block size (bytes) .*$/-block size (bytes) $block_size/" \
            -e "s/^-associativity .*$/-associativity $associativity/" \
            "$CFG_BASE" > "$cfg_novo"
        
        # Executar CACTI e salvar resultados
        saida="${DIR_RESULTADOS}/resultado_${TAMANHO_CACHE}_${block_size}_${associativity}.out"
        
        # Executar CACTI capturando toda a saída
        ./cacti -infile "$cfg_novo" > "$saida" 2>&1 || {
            # Adicionar informações detalhadas em caso de erro
            echo -e "\n\n=== DETALHES DO ERRO ===" >> "$saida"
            echo "Parâmetros usados:" >> "$saida"
            grep -E "^-size|^-block size|^-associativity" "$cfg_novo" >> "$saida"
            
            # Calcular e mostrar métricas importantes
            local num_blocos=$((TAMANHO_CACHE / block_size))
            local num_conjuntos=$((associativity == 0 ? 1 : num_blocos / associativity))
            echo -e "\nNúmero de blocos: $num_blocos" >> "$saida"
            echo "Número de conjuntos: $num_conjuntos" >> "$saida"
            
            # Tentar identificar a causa do erro
            if grep -q "no valid data array organizations found" "$saida"; then
                echo -e "\nCAUSA PROVÁVEL:" >> "$saida"
                echo "O CACTI não conseguiu encontrar uma organização física viável para a cache" >> "$saida"
                echo "com apenas $num_conjuntos conjunto(s) e blocos de $block_size bytes." >> "$saida"
            fi
            
            # Registrar no log geral
            echo "Erro na execução: Size=$TAMANHO_CACHE Block=$block_size Assoc=$associativity" >> "$LOG_ERROS"
        }
        
        echo "Teste concluído: Size=${TAMANHO_CACHE} Block=${block_size} Assoc=${associativity}"
    done
done

echo "Todos os testes foram concluídos! Resultados em: $DIR_RESULTADOS/"
echo "Log de erros em: $LOG_ERROS"