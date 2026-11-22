# ofmana

Application web de gestion d'agence, avec deux espaces :

- **Admin (agence)** : fiches modèles, prospection en glisser-déposer, statistiques, planning de contenu, tâches.
- **Modèle** : chaque modèle se connecte et voit uniquement son planning, ses revenus et sa part, et les tâches que l'agence partage avec elle.

Interface sombre, effet verre, accents violet et magenta. Le site tient dans un seul fichier, `index.html`, et ne demande aucune étape de build. Il est hébergé sur GitHub Pages, et les comptes et les données sont stockés sur Supabase.

**Mise en route : voir [SETUP.md](SETUP.md).**

## Fichiers

| Fichier | Rôle |
|---|---|
| `index.html` | L'application complète (interface, connexion, synchronisation) |
| `config.js` | Adresse et clé publique du projet Supabase |
| `supabase/setup.sql` | Tables, règles de sécurité (Row Level Security) et fonctions |
| `SETUP.md` | Guide d'installation pas à pas |

## Sécurité

- Les droits d'accès sont appliqués par la base de données (Row Level Security), pas seulement par l'interface. Une modèle ne peut lire que sa fiche, ses contenus et les tâches marquées « Visible par elle ». Elle ne peut rien modifier, à part cocher ses tâches.
- Les notes de l'agence sur chaque modèle sont stockées dans une table séparée, réservée à l'admin.
- Le premier compte créé devient l'admin. Les comptes suivants sont des comptes modèles, reliés à leur fiche par leur email.
- Ce dépôt ne contient aucune donnée : tout est stocké dans Supabase.
