import os
import re
import csv
import matplotlib.pyplot as plt
import pandas as pd

# Configurações
RESULTS_DIR = "resultados_cacti"
OUTPUT_CSV = "cacti_results_summary.csv"
ERROR_LOG = "cacti_analysis_errors.log"

# Padrões regex para extração de dados
PATTERNS = {
    "cache_size": r"Cache size\s*:\s*(\d+)",
    "block_size": r"Block size\s*:\s*(\d+)",
    "associativity": r"Associativity\s*:\s*(\d+|0)",
    "access_time": r"Access time \(ns\):\s*([\d.]+)",
    "cycle_time": r"Cycle time \(ns\):\s*([\d.]+)",
    "read_energy": r"Read Energy \(nJ\):\s*([\d.]+)",
    "write_energy": r"Write Energy \(nJ\):\s*([\d.]+)",
    "leakage_power": r"Leakage Power Closed Page \(mW\):\s*([\d.]+)",
    "area": r"Cache height x width \(mm\):\s*([\d.]+) x ([\d.]+)",
    "sets": r"Number of sets\s*:\s*(\d+)",
    "banks": r"Cache banks \(UCA\)\s*:\s*(\d+)"
}

def extract_metrics(file_path):
    """Extrai métricas de um arquivo de resultados do CACTI"""
    # Tentar ler com diferentes codificações
    content = None
    encodings = ['utf-8', 'latin-1', 'cp1252', 'iso-8859-1']
    for encoding in encodings:
        try:
            with open(file_path, 'r', encoding=encoding) as f:
                content = f.read()
            break
        except UnicodeDecodeError:
            continue
    
    if content is None:
        # Se todas as codificações falharem, tentar com ignorar erros
        try:
            with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()
        except Exception as e:
            return {"status": "error", "reason": f"Erro de leitura: {str(e)}"}
    
    # Verificar se é uma configuração inválida
    if "CONFIGURAÇÃO INVÁLIDA" in content:
        return {"status": "invalid", "reason": content.split("Motivo:")[1].strip() if "Motivo:" in content else "Invalid configuration"}
    
    if "ERRO NA EXECUÇÃO" in content or "ERROR" in content:
        return {"status": "error", "reason": "Runtime error"}
    
    # Extrair parâmetros do nome do arquivo
    filename = os.path.basename(file_path)
    parts = filename.split('_')
    metrics = {
        "cache_size": parts[1] if len(parts) > 1 else "2048",
        "block_size": parts[2] if len(parts) > 2 else "?",
        "associativity": parts[3].split('.')[0] if len(parts) > 3 else "?",
        "status": "valid"
    }
    
    # Extrair métricas usando regex
    for key, pattern in PATTERNS.items():
        match = re.search(pattern, content)
        if match:
            if key == "area":
                try:
                    metrics["height_mm"] = float(match.group(1))
                    metrics["width_mm"] = float(match.group(2))
                    metrics["area_mm2"] = metrics["height_mm"] * metrics["width_mm"]
                except ValueError:
                    pass
            else:
                try:
                    metrics[key] = float(match.group(1)) if match.group(1).replace('.', '', 1).isdigit() else match.group(1)
                except:
                    metrics[key] = match.group(1)
    
    # Calcular métricas derivadas
    if "access_time" in metrics and "cycle_time" in metrics:
        try:
            metrics["efficiency"] = float(metrics["access_time"]) / float(metrics["cycle_time"])
        except:
            pass
    
    return metrics

def analyze_results():
    """Analisa todos os resultados e gera relatórios"""
    all_metrics = []
    error_count = 0
    valid_count = 0
    
    print(f"Analisando resultados em {RESULTS_DIR}...")
    
    # Processar todos os arquivos de resultados
    for filename in os.listdir(RESULTS_DIR):
        if filename.endswith(".out"):
            file_path = os.path.join(RESULTS_DIR, filename)
            metrics = extract_metrics(file_path)
            metrics["filename"] = filename
            all_metrics.append(metrics)
            
            if metrics["status"] in ["error", "invalid"]:
                error_count += 1
            else:
                valid_count += 1
    
    # Salvar relatório CSV
    with open(OUTPUT_CSV, 'w', newline='', encoding='utf-8') as csvfile:
        fieldnames = [
            "filename", "status", "cache_size", "block_size", "associativity",
            "access_time", "cycle_time", "read_energy", "write_energy",
            "leakage_power", "area_mm2", "efficiency", "sets", "banks"
        ]
        
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
        writer.writeheader()
        
        for metrics in all_metrics:
            # Preencher valores ausentes para configurações inválidas
            row = {field: metrics.get(field, "N/A") for field in fieldnames}
            writer.writerow(row)
    
    print(f"\nResultados analisados: {len(all_metrics)}")
    print(f"  Configurações válidas: {valid_count}")
    print(f"  Configurações inválidas/erros: {error_count}")
    print(f"Relatório CSV salvo em: {OUTPUT_CSV}")
    
    return all_metrics

def visualize_results(df):
    """Cria visualizações dos resultados válidos"""
    valid_df = df[df["status"] == "valid"]
    
    if valid_df.empty:
        print("Nenhum dado válido para visualização.")
        return
    
    # Configurar estilo dos gráficos
    plt.style.use('seaborn-v0_8-darkgrid')
    plt.rcParams.update({'font.size': 10})
    
    print("\nCriando visualizações...")
    
    # Converter colunas para float
    for col in ['access_time', 'cycle_time', 'read_energy', 'write_energy', 'leakage_power', 'area_mm2', 'efficiency']:
        valid_df[col] = pd.to_numeric(valid_df[col], errors='coerce')
    
    # Remover linhas com valores NaN
    valid_df = valid_df.dropna(subset=['access_time', 'read_energy', 'area_mm2'])
    
    # Gráfico 1: Tempo de acesso por configuração
    plt.figure(figsize=(12, 8))
    for block_size in valid_df["block_size"].unique():
        subset = valid_df[valid_df["block_size"] == block_size]
        plt.plot(
            subset["associativity"], 
            subset["access_time"],
            'o-', 
            label=f"Block: {block_size}B"
        )
    
    plt.title("Tempo de Acesso por Configuração")
    plt.xlabel("Associatividade")
    plt.ylabel("Tempo de Acesso (ns)")
    plt.legend()
    plt.grid(True)
    plt.savefig("access_time_comparison.png", dpi=300)
    plt.close()
    
    # Gráfico 2: Consumo energético
    plt.figure(figsize=(12, 8))
    for associativity in valid_df["associativity"].unique():
        subset = valid_df[valid_df["associativity"] == associativity]
        plt.plot(
            subset["block_size"], 
            subset["read_energy"],
            's--', 
            label=f"Assoc: {associativity}"
        )
    
    plt.title("Energia de Leitura por Configuração")
    plt.xlabel("Tamanho do Bloco (bytes)")
    plt.ylabel("Energia de Leitura (nJ)")
    plt.legend()
    plt.grid(True)
    plt.savefig("read_energy_comparison.png", dpi=300)
    plt.close()
    
    # Gráfico 3: Área ocupada
    plt.figure(figsize=(12, 8))
    scatter = plt.scatter(
        valid_df["access_time"],
        valid_df["area_mm2"],
        c=pd.to_numeric(valid_df["block_size"], errors='coerce'),
        s=pd.to_numeric(valid_df["associativity"], errors='coerce') * 20,
        cmap="viridis",
        alpha=0.7
    )
    
    plt.colorbar(scatter, label="Tamanho do Bloco (bytes)")
    plt.title("Relação entre Tempo de Acesso e Área Ocupada")
    plt.xlabel("Tempo de Acesso (ns)")
    plt.ylabel("Área (mm²)")
    plt.grid(True)
    plt.savefig("area_vs_access.png", dpi=300)
    plt.close()
    
    print("Visualizações salvas como PNG")

def main():
    # Criar diretório de resultados se não existir
    if not os.path.exists(RESULTS_DIR):
        os.makedirs(RESULTS_DIR)
        print(f"Diretório {RESULTS_DIR} criado. Por favor, coloque os arquivos de resultados nele.")
        return
    
    # Analisar resultados
    results = analyze_results()
    
    # Carregar dados para visualização
    try:
        df = pd.read_csv(OUTPUT_CSV, encoding='utf-8')
        visualize_results(df)
        
        # Mostrar resumo estatístico
        print("\nResumo estatístico para configurações válidas:")
        valid_df = df[df["status"] == "valid"]
        
        # Converter colunas numéricas
        numeric_cols = ['access_time', 'cycle_time', 'read_energy', 'write_energy', 
                       'leakage_power', 'area_mm2', 'efficiency']
        for col in numeric_cols:
            valid_df[col] = pd.to_numeric(valid_df[col], errors='coerce')
        
        if not valid_df.empty:
            print(valid_df[numeric_cols].describe())
        
    except Exception as e:
        print(f"Erro ao gerar visualizações: {str(e)}")
        with open(ERROR_LOG, "a", encoding='utf-8') as f:
            f.write(f"Erro: {str(e)}\n")

if __name__ == "__main__":
    main()