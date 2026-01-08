graph TB
    subgraph "Project Root"
        A["📁 project-root"]
    end
    
    subgraph "Infrastructure Layer"
        B["🏗️ terraform/"]
        B1["📦 modules/"]
        B2["🌍 environments/"]
        B1_1["networking"]
        B1_2["compute"]
        B1_3["storage"]
        B1_4["kubernetes"]
        B2_1["dev/"]
        B2_2["staging/"]
        B2_3["production/"]
    end
    
    subgraph "Application Layer"
        C["📊 helm/"]
        C1["📋 charts/"]
        C2["🎯 values/"]
        C1_1["app-service"]
        C1_2["infrastructure"]
    end
    
    subgraph "Documentation & Automation"
        D["📚 docs/"]
        E["🔧 scripts/"]
        F["⚙️ Config Files"]
        D1["terraform/"]
        D2["helm/"]
        D3["examples/"]
        F1[".gitignore"]
        F2[".pre-commit-config"]
        F3["Makefile"]
    end
    
    A --> B
    A --> C
    A --> D
    A --> E
    A --> F
    
    B --> B1
    B --> B2
    B1 --> B1_1
    B1 --> B1_2
    B1 --> B1_3
    B1 --> B1_4
    B2 --> B2_1
    B2 --> B2_2
    B2 --> B2_3
    
    C --> C1
    C --> C2
    C1 --> C1_1
    C1 --> C1_2
    
    D --> D1
    D --> D2
    D --> D3
    
    B2_1 -.->|uses| B1
    B2_2 -.->|uses| B1
    B2_3 -.->|uses| B1
    
    C1_1 -.->|deployed on| B1_4
    C1_2 -.->|deployed on| B1_4
    
    E -.->|executes| B
    E -.->|executes| C
    
    style A fill:#e1f5ff
    style B fill:#fff3e0
    style C fill:#f3e5f5
    style D fill:#e8f5e9
    style E fill:#fce4ec
    style F fill:#f1f8e9
