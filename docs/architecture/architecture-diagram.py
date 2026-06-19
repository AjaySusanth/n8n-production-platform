import os
import shutil
from diagrams import Diagram, Cluster, Edge, Node
from diagrams.azure.compute import ContainerRegistries
from diagrams.azure.security import KeyVaults
from diagrams.azure.network import PublicIpAddresses
from diagrams.azure.database import CacheForRedis, DatabaseForPostgresqlServers
from diagrams.k8s.compute import Pod
from diagrams.k8s.network import Ingress
from diagrams.custom import Custom

# ── Graphviz path (Windows-only, conditional) ─────────────────────────────────
graphviz_win_path = r"C:\Program Files\Graphviz\bin"
if os.path.exists(graphviz_win_path):
    os.environ["PATH"] += os.pathsep + graphviz_win_path

# ── Working directory ─────────────────────────────────────────────────────────
script_dir = os.path.dirname(os.path.abspath(__file__)) if __file__ else "."
os.chdir(script_dir)

# ── Custom logos ──────────────────────────────────────────────────────────────
for img in ["n8n.png", "keda.png"]:
    root_path = os.path.join("..", "..", img)
    if os.path.exists(root_path):
        shutil.copy(root_path, img)

# ── Semantic edge definitions (penwidth signals priority) ─────────────────────
EDGE_INGRESS = Edge(color="#e8742a", style="solid",  penwidth="2.5")
EDGE_DB      = Edge(color="#2a6ae8", style="solid",  penwidth="2.0")
EDGE_KEDA    = Edge(color="#9b30d9", style="dashed", penwidth="1.5")
EDGE_PULL    = Edge(color="#888888", style="dashed", penwidth="1.0")
EDGE_CSI     = Edge(color="#9b30d9", style="dotted", penwidth="1.0")

# ── Graph-level attributes ────────────────────────────────────────────────────
graph_attr = {
    "splines":   "ortho",                                   # 90-degree routing
    "fontname":  "Arial, sans-serif",
    "fontsize":  "14",
    "bgcolor":   "white",
    "pad":       "1.0",    # outer margin
    "nodesep":   "0.8",    # horizontal breathing room
    "ranksep":   "1.2",    # vertical breathing room
    "arrowsize": "0.7",    # proportionate arrowheads
}

# ── Node-level defaults (height=1.8 gives clearance to avoid text overlap) ─────
node_attr = {
    "fontsize": "11",
    "fontname": "Arial, sans-serif",
    "width":    "1.6",
    "height":   "1.8",     # Increased height to push labels cleanly below icons
}

# ── Cluster style presets (font configuration added for legibility) ───────────
CLUSTER_AZURE = {   # Managed Azure services zone
    "style":     "filled",
    "fillcolor": "#EBF3FB",
    "pencolor":  "#0078D4",   # Microsoft Azure brand blue
    "fontcolor": "#0078D4",
    "fontname":  "Arial, sans-serif",
    "fontsize":  "12",
    "penwidth":  "2",
}
CLUSTER_VNET = {    # VNet / Subnet boundary
    "style":     "filled",
    "fillcolor": "#F7F7F7",
    "pencolor":  "#BBBBBB",
    "fontcolor": "#555555",
    "fontname":  "Arial, sans-serif",
    "fontsize":  "12",
    "penwidth":  "1",
}
CLUSTER_AKS = {     # AKS cluster
    "style":     "filled",
    "fillcolor": "#F0F4F8",
    "pencolor":  "#326CE5",   # Kubernetes logo blue
    "fontcolor": "#326CE5",
    "fontname":  "Arial, sans-serif",
    "fontsize":  "12",
    "penwidth":  "2",
}
CLUSTER_NS_PRIMARY = {   # dev namespace
    "style":     "filled",
    "fillcolor": "#EDF7ED",
    "pencolor":  "#28A745",
    "fontcolor": "#155724",
    "fontname":  "Arial, sans-serif",
    "fontsize":  "12",
    "penwidth":  "2.5",
}
CLUSTER_NS_SUPPORT = {   # supporting namespaces
    "style":     "filled",
    "fillcolor": "#F9F9F9",
    "pencolor":  "#AAAAAA",
    "fontcolor": "#555555",
    "fontname":  "Arial, sans-serif",
    "fontsize":  "11",
    "penwidth":  "1",
}
CLUSTER_LEGEND = {  # legend box
    "style":     "filled",
    "fillcolor": "#F9F9F9",
    "pencolor":  "#CCCCCC",
    "fontcolor": "#333333",
    "fontname":  "Arial, sans-serif",
    "fontsize":  "11",
    "penwidth":  "1",
}

# ── Diagram ───────────────────────────────────────────────────────────────────
with Diagram(
    name="n8n Production Platform — Core Topology",
    show=False,
    direction="LR",
    graph_attr=graph_attr,
    node_attr=node_attr,
    filename="architecture-diagram",
):
    # ── External entry point ──────────────────────────────────────────────────
    user = PublicIpAddresses("External Clients\n(HTTPS / 443)")

    # ── Managed Azure Services ────────────────────────────────────────────────
    with Cluster("Managed Azure Services\n(ACR · Key Vault)", graph_attr=CLUSTER_AZURE):
        acr = ContainerRegistries("ACR: n8ndevacrajay789")
        kv  = KeyVaults("Key Vault: n8n-dev-kv-ajay789")

    # ── Virtual Network ───────────────────────────────────────────────────────
    with Cluster("VNet: n8n-dev-vnet  [10.240.0.0/16]", graph_attr=CLUSTER_VNET):
        with Cluster("Subnet: n8n-dev-subnet  [10.240.0.0/22]", graph_attr=CLUSTER_VNET):

            # ── AKS Cluster ───────────────────────────────────────────────────
            with Cluster(
                "AKS Cluster: n8n-dev-aks  (Kubernetes 1.33 · Standard_B2s_v2)",
                graph_attr=CLUSTER_AKS,
            ):
                # CSI Driver — inherits default node size and font spacing
                csi_driver = Pod("CSI Driver\n(secrets-store)")

                # ns: ingress-nginx ────────────────────────────────────────────
                with Cluster("ns: ingress-nginx", graph_attr=CLUSTER_NS_SUPPORT):
                    ingress_ctrl = Ingress("NGINX Ingress Controller")

                # ns: keda ─────────────────────────────────────────────────────
                with Cluster("ns: keda", graph_attr=CLUSTER_NS_SUPPORT):
                    keda_operator = Custom("KEDA Operator", "keda.png")

                # ns: dev (primary workload zone) ──────────────────────────────
                with Cluster("ns: dev", graph_attr=CLUSTER_NS_PRIMARY):
                    n8n_main    = Custom("n8n-main\n(UI & API)",           "n8n.png")
                    n8n_webhook = Custom("n8n-webhook\n(Webhook receiver)", "n8n.png")
                    n8n_worker  = Custom("n8n-worker\n(Job processor)",     "n8n.png")
                    postgres    = DatabaseForPostgresqlServers("n8n-postgres\n(StatefulSet)")
                    redis       = CacheForRedis("n8n-redis\n(StatefulSet)")

    # ── Legend ────────────────────────────────────────────────────────────────
    with Cluster("Legend", graph_attr=CLUSTER_LEGEND):
        def leg(label, edge_style):
            src = Node("", shape="none", width="0.01", height="0.01")
            dst = Node(label, shape="none", width="1.8", height="0.3")
            src >> edge_style >> dst

        leg("Ingress routing  (HTTP 5678)",     Edge(color="#e8742a", style="solid",  penwidth="2.5"))
        leg("DB & queue traffic  (5432 / 6379)", Edge(color="#2a6ae8", style="solid",  penwidth="2.0"))
        leg("KEDA autoscale & queue poll",       Edge(color="#9b30d9", style="dashed", penwidth="1.5"))
        leg("Secrets via Key Vault CSI",         Edge(color="#9b30d9", style="dotted", penwidth="1.0"))
        leg("OCI image pull  (ACR)",             Edge(color="#888888", style="dashed", penwidth="1.0"))

    # ── Edges ─────────────────────────────────────────────────────────────────

    # 1. Ingress traffic routing
    user         >> EDGE_INGRESS >> ingress_ctrl
    ingress_ctrl >> EDGE_INGRESS >> [n8n_main, n8n_webhook]

    # 2. Database & broker communication
    [n8n_main, n8n_webhook, n8n_worker] >> EDGE_DB >> postgres
    [n8n_main, n8n_webhook, n8n_worker] >> EDGE_DB >> redis

    # 3. KEDA autoscaling
    keda_operator >> EDGE_KEDA >> n8n_worker
    keda_operator >> EDGE_KEDA >> redis

    # 4. OCI image pulls from ACR (collapsed fan-out)
    acr >> EDGE_PULL >> [n8n_main, n8n_webhook, n8n_worker, postgres, redis]

    # 5. Secrets Store CSI (collapsed fan-in → fan-out)
    [n8n_main, n8n_webhook, n8n_worker, postgres, redis] >> EDGE_CSI >> csi_driver
    csi_driver >> EDGE_CSI >> kv
