const express = require('express');
const { createServer } = require('node:http');
const { join } = require('node:path');
const { Server } = require('socket.io');
const os = require('os');
const app = express();
const server = createServer(app);
const io = new Server(server, { 
    cors: { origin: "*", methods: ["GET", "POST"] },
    transports: ['websocket', 'polling']
});
const port = process.env.PORT || 3000;

app.use(express.static(join(__dirname, '../maxiflop-smartphone')));
app.get('/', (req, res) => res.sendFile(join(__dirname, '../maxiflop-smartphone/index.html')));

// Structure globale pour stocker plusieurs sessions en parallèle
const sessions = {}; 

const publicUrl = process.env.RENDER_EXTERNAL_URL || process.env.PUBLIC_URL || `http://localhost:${port}`;
console.log(`\n=== URL PUBLIQUE ===\n${publicUrl}\n===================\n`);

// Helper pour créer un état de jeu vierge pour une room
function createInitialGameState(roomCode) {
    return {
        roomCode: roomCode,
        status: "lobby",
        teams: [
            { name: "Equipe1", players: [] },
            { name: "Equipe2", players: [] },
            { name: "Equipe3", players: [] }
        ],
        players: {},
        teamScores: { "Equipe1": 0, "Equipe2": 0, "Equipe3": 0 },
        availableMusics: [],
        playerVotes: {},
        gameMode: "NORMAL"
    };
}

function sendLobbyToGodot(roomCode) {
    const session = sessions[roomCode];
    if (!session || !session.godotHost) return;

    const playersArr = Object.keys(session.gameState.players).map(id => ({
        id: id,
        pseudo: session.gameState.players[id].pseudo,
        team: session.gameState.players[id].team
    }));

    session.godotHost.emit("lobby_update", {
        players: playersArr,
        teamScores: { ...session.gameState.teamScores },
        publicUrl: publicUrl
    });
}

function envoyerVotesAGodot(roomCode) {
    const session = sessions[roomCode];
    if (!session || session.gameState.status !== "voting") return;

    const choix = {};
    const totalVotes = Object.keys(session.gameState.playerVotes).length;

    if (totalVotes === 0) {
        io.to(roomCode).emit("vote_update", []);
        return;
    }

    Object.values(session.gameState.playerVotes).forEach(song => {
        choix[song] = (choix[song] || 0) + 1;
    });

    const statsTrie = Object.keys(choix)
        .map(songName => ({
            songName,
            votes: choix[songName],
            percentage: Math.round((choix[songName] / totalVotes) * 100)
		}))
		.sort((a, b) => b.votes - a.votes)
		.slice(0, 3);

    io.to(roomCode).emit("vote_update", statsTrie);
}

io.on('connection', (socket) => {
    console.log('User connecté globalement :', socket.id);
    
    // Garder trace de la room du socket actuel pour simplifier les déconnexions
    let currentRoomCode = null;

    // ─── HÔTE GODOT REJOINT ──────────────────────────────────────────────────
    socket.on('host_join', (data) => {
        const roomCode = (data && data.roomCode) ? data.roomCode.toUpperCase() : "DEFAULT";
        currentRoomCode = roomCode;
        
        socket.join(roomCode);
        console.log(`Godot Host connecté à la Session : ${roomCode}`);

        // Initialisation de la session si inexistante
        sessions[roomCode] = {
            godotHost: socket,
            gameState: createInitialGameState(roomCode)
        };

        if (publicUrl) {
            socket.emit('public_url', { url: publicUrl });
        }

        sendLobbyToGodot(roomCode);
        io.to(roomCode).emit('update-lobby', sessions[roomCode].gameState);
    });

    // ─── VÉRIFICATION DU CODE PAR LE SMARTPHONE ──────────────────────────────
    socket.on('verify-room', (roomCode, callback) => {
        const code = roomCode.toUpperCase().trim();
        if (sessions[code]) {
            callback({ valid: true });
        } else {
            callback({ valid: false, error: "Code de session inconnu !" });
        }
    });

    // ─── MANETTE REJOINT UNE SESSION ─────────────────────────────────────────
    socket.on('join-game', (data) => {
        const roomCode = data.roomCode ? data.roomCode.toUpperCase().trim() : "";
        const pseudo = data.pseudo;

        if (!sessions[roomCode]) {
            socket.emit('error-lancement', 'Cette session n\'existe plus.');
            return;
        }

        currentRoomCode = roomCode;
        socket.join(roomCode);

        const session = sessions[roomCode];
        session.gameState.players[socket.id] = { pseudo, team: 'Equipe1', score: 0 };
        
        socket.emit('update-lobby', session.gameState);
        io.to(roomCode).emit('update-lobby', session.gameState);
        sendLobbyToGodot(roomCode);
    });

    // ─── ROUTAGE DES INSTRUCTIONS (RESTE DES ÉVÉNEMENTS) ─────────────────────
    socket.on('host_phase', (data) => {
        if (!currentRoomCode || !sessions[currentRoomCode]) return;
        const session = sessions[currentRoomCode];
        const gameState = session.gameState;
        
        gameState.gameMode = data.gameMode || "NORMAL";

        if (gameState.status === "voting" && data.phase !== "voting") {
            const choix = {};
            Object.values(gameState.playerVotes).forEach(song => { choix[song] = (choix[song] || 0) + 1; });

            let winner = "";
            let maxVotes = -1;
            Object.keys(choix).forEach(song => {
                if (choix[song] > maxVotes) { maxVotes = choix[song]; winner = song; }
            });
            if (!winner && gameState.availableMusics.length > 0) {
                winner = gameState.availableMusics[Math.floor(Math.random() * gameState.availableMusics.length)];
            }
            io.to(currentRoomCode).emit('vote_result', { winner });

        } else if (data.phase === "voting") {
            if (gameState.status !== "voting") {
                gameState.status = "voting";
                gameState.playerVotes = {};
            }
            envoyerVotesAGodot(currentRoomCode);
        } else if (data.phase === "reveal" || data.phase === "countdown") {
            gameState.status = data.phase;
        } else if (data.phase === "lobby" || data.phase === "ended") {
            gameState.status = "lobby";
            gameState.playerVotes = {};
        }

        io.to(currentRoomCode).emit('host_phase', data);
    });

    socket.on('join-team', (teamName) => {
        if (!currentRoomCode || !sessions[currentRoomCode]) return;
        const session = sessions[currentRoomCode];
        const player = session.gameState.players[socket.id];
        const team = session.gameState.teams.find(t => t.name === teamName);
        if (!player || !team) return;

        if (player.team) {
            const ancienneTeam = session.gameState.teams.find(t => t.name === player.team);
            if (ancienneTeam) ancienneTeam.players = ancienneTeam.players.filter(id => id !== socket.id);
        }

        player.team = teamName;
        team.players.push(socket.id);
        io.to(currentRoomCode).emit('update-lobby', session.gameState);
        sendLobbyToGodot(currentRoomCode);
    });

    socket.on('player_input', (data) => {
        if (!currentRoomCode || !sessions[currentRoomCode]) return;
        const session = sessions[currentRoomCode];
        if (session.godotHost) {
            session.godotHost.emit('player_input', {
                playerId: socket.id,
                color: Number(data.color),
                clientTs: Number(data.clientTs || Date.now()),
                serverTs: Date.now()
            });
        }
    });

    socket.on('feedback', (data) => {
        if (data.playerId) io.to(data.playerId).emit('feedback', data);
    });

    socket.on('scoreboard', (data) => {
        if (!currentRoomCode || !sessions[currentRoomCode]) return;
        const session = sessions[currentRoomCode];
        if (data.players) {
            data.players.forEach(p => {
                if (session.gameState.players[p.id]) {
                    session.gameState.players[p.id].score = p.score;
                    session.gameState.players[p.id].combo = p.combo;
                    session.gameState.players[p.id].perfect_streak = p.perfect_streak;
                }
            });
        }
        if (data.teamScores) {
            Object.assign(session.gameState.teamScores, data.teamScores);
        }
    });

    socket.on('music_list', (data) => {
        if (!currentRoomCode || !sessions[currentRoomCode]) return;
        sessions[currentRoomCode].gameState.availableMusics = data.musics || [];
        io.to(currentRoomCode).emit('music_list', data.musics);
    });

    socket.on('vote', (data) => {
        if (!currentRoomCode || !sessions[currentRoomCode]) return;
        const session = sessions[currentRoomCode];
        const match = session.gameState.availableMusics.find(m => m.trim().toLowerCase() === data.songName.trim().toLowerCase());
        session.gameState.playerVotes[socket.id] = match || data.songName;
        envoyerVotesAGodot(currentRoomCode);
    });

    socket.on('player_eliminated', (data) => {
        if (data.playerId) io.to(data.playerId).emit('eliminated', { status: true });
    });

    socket.on('disconnect', () => {
        if (!currentRoomCode || !sessions[currentRoomCode]) return;
        const session = sessions[currentRoomCode];

        if (session.godotHost === socket) {
            console.log(`Godot Host déconnecté de la session ${currentRoomCode}. Fermeture.`);
            io.to(currentRoomCode).emit('error-lancement', 'L\'écran principal s\'est déconnecté.');
            delete sessions[currentRoomCode];
            return;
        }

        const player = session.gameState.players[socket.id];
        if (!player) return;

        if (player.team) {
            const team = session.gameState.teams.find(t => t.name === player.team);
            if (team) team.players = team.players.filter(id => id !== socket.id);
        }

        delete session.gameState.players[socket.id];
        io.to(currentRoomCode).emit('update-lobby', session.gameState);
        session.godotHost.emit("player_left", { playerId: socket.id });
        sendLobbyToGodot(currentRoomCode);
    });
});

server.listen(port, "0.0.0.0", () => {
    console.log(`\nServeur multisession actif sur le port : ${port}`);
});
