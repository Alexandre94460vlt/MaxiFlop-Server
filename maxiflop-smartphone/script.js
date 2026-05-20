const nameInput = document.getElementById("nameInput");
const statusText = document.getElementById("status");
const teamInfo = document.getElementById("teamInfo");
const scoreText = document.getElementById("scoreText");
const rankText = document.getElementById("rankText");
const feedbackText = document.getElementById("feedback");
const timerDisplay = document.getElementById("timerDisplay");

const screens = {
	login: document.getElementById("login"),
	waiting: document.getElementById("waiting"),
	controller: document.getElementById("controller"),
	vote: document.getElementById("vote"),
	rotate: document.getElementById("rotate"),
	eliminated: document.getElementById("eliminated-screen")
};

const showScreen = (key) => {
	Object.values(screens).forEach((el) => el.classList.add("hidden"));
	screens[key].classList.remove("hidden");
};

const socket = io();

document.querySelectorAll(".join-team-btn").forEach((btn) => {
	btn.addEventListener("click", () => {
		const teamName = btn.dataset.team;
		joinGame(teamName);
	});
});

function joinGame(teamName) {
	const name = nameInput.value.trim();
	if (!name) {
		statusText.textContent = "Entrez un pseudo d'abord !";
		return;
	}

	statusText.textContent = "Connexion...";
	localStorage.setItem("maxiflop_name", name);
	localStorage.setItem("maxiflop_team", teamName);

	socket.emit("join-game", name);

	setTimeout(() => {
		socket.emit("join-team", teamName);
		showScreen("waiting");
	}, 100);
}

socket.on("update-lobby", (gameState) => {
	// Dynamically update team selection buttons correctly based on active teams logic
	const teamCounts = {};
	gameState.teams.forEach(t => teamCounts[t.name] = t.players.length || 0);

	document.querySelectorAll(".join-team-btn").forEach((btn) => {
		const targetTeam = btn.dataset.team;
		const counts = { ...teamCounts };
		counts[targetTeam] = (counts[targetTeam] || 0) + 1; // Simulate joining
		
		const sizes = Object.values(counts);
		const max = Math.max(...sizes);
		const min = Math.min(...sizes);
		let isValid = (max - min <= 2);
		
		btn.disabled = !isValid;
		if (!isValid) btn.classList.add("disabled");
		else btn.classList.remove("disabled");
	});

	// Gestion du mode Battle Royale
	// Support du mode dans gameState ou gameState.gameMode (uniformisation)
	const mode = gameState.gameMode || gameState.currentMode || "NORMAL";
	const isBR = (mode === "BATTLE_ROYALE");
	document.querySelector(".team-btns").classList.toggle("hidden", isBR);
	
	const title = document.querySelector("#teamSelection p");
	if (title) title.textContent = isBR ? "Prêt pour le massacre ?" : "Choisis ton équipe :";

	const myPlayer = gameState.players[socket.id];
	if (!myPlayer || !myPlayer.team) return;

	if (isBR) {
		teamInfo.textContent = "Tu es prêt pour le massacre !";
		if (!rankText.textContent.includes("ÉLIMINÉ")) {
			rankText.textContent = `Rang ?`;
		}
		rankText.className = "team-br"; 
	} else {
		teamInfo.textContent = `Tu es dans l'${myPlayer.team} !`;
		if (!rankText.textContent.includes("Rang")) {
			rankText.textContent = `Rang ? - ${myPlayer.team}`;
		}
		if (myPlayer.team === "Equipe1") rankText.className = "team-blue";
		else if (myPlayer.team === "Equipe2") rankText.className = "team-red";
		else rankText.className = "team-yellow";
	}
});

// Écoute des phases de la partie, dictées par Godot
socket.on("host_phase", (data) => {
	if (data.phase === "countdown" || data.phase === "reveal") {
		showScreen("rotate");
	} else if (data.phase === "playing") {
		feedbackText.textContent = "GO !";
		document.body.classList.add("playing");
		showScreen("controller");
	} else if (data.phase === "lobby" || data.phase === "ended") {
		document.body.classList.remove("playing");
		showScreen("waiting");
		timerDisplay.textContent = "En attente du lancement par l'écran principal...";
		// Remise à zéro visuelle pour la prochaine partie
		scoreText.textContent = "0";
		feedbackText.textContent = "Pret ?";
	} else if (data.phase === "voting") {
		showScreen("vote");
	}
});

socket.on("error-lancement", (msg) => {
	alert("Erreur de lancement : " + msg);
});

socket.on("desequilibre", (teams) => {
	alert("Équipes déséquilibrées ! Il faut s'équilibrer pour que la partie puisse démarrer.");
});

socket.on("feedback", (msg) => {
	const sign = msg.points > 0 ? "+" : "";
	feedbackText.textContent = `${msg.result} (${sign}${msg.points})`;
	scoreText.textContent = `${msg.score}`;

	const teamName = localStorage.getItem("maxiflop_team") || "???";
	if (msg.rank) {
		rankText.textContent = `Rang #${msg.rank} - ${teamName}`;
	}

	triggerVibration(msg.result);
});

socket.on("music_list", (musics) => {
	const musicList = document.getElementById("musicList");
	musicList.innerHTML = "";
	musics.forEach((song) => {
		const item = document.createElement("div");
		item.className = "music-item";
		
		let displayName = song;
		if (song.toUpperCase().endsWith("EASY")) {
			item.classList.add("diff-easy");
			displayName = song.substring(0, song.length - 7);
		} else if (song.toUpperCase().endsWith("MEDIUM")) {
			item.classList.add("diff-medium");
			displayName = song.substring(0, song.length - 9);
		} else if (song.toUpperCase().endsWith("HARD")) {
			item.classList.add("diff-hard");
			displayName = song.substring(0, song.length - 7);
		} else if (song.toUpperCase().endsWith("EXTREME")) {
			item.classList.add("diff-extreme");
			displayName = song.substring(0, song.length - 10);
		}
		
		item.textContent = displayName.trim();
		item.onclick = () => {
			document.querySelectorAll(".music-item").forEach(el => el.classList.remove("selected"));
			item.classList.add("selected");
			socket.emit("vote", { songName: song });
		};
		musicList.appendChild(item);
	});
});

socket.on("vote_result", (data) => {
	// Optionnel : on pourrait afficher le gagnant sur le téléphone aussi
	console.log("Winner is:", data.winner);
});

socket.on("eliminated", (data) => {
	if (data.status) {
		showScreen("eliminated");
		if (navigator.vibrate) navigator.vibrate([100, 50, 100, 50, 300]); // Vibration de défaite
	}
});

// Détections PC / Mobile pour les hints clavier
const isTouchDevice = 'ontouchstart' in window || navigator.maxTouchPoints > 0;
if (!isTouchDevice) {
	document.body.classList.add("is-pc");
	// Ajouter visuellement les lettres X, C, V dans les boutons
	const btnBlue = document.querySelector('.btn.blue');
	const btnYellow = document.querySelector('.btn.yellow');
	const btnRed = document.querySelector('.btn.red');
	if (btnBlue) btnBlue.innerHTML = '<span class="key-hint">X</span>';
	if (btnYellow) btnYellow.innerHTML = '<span class="key-hint">C</span>';
	if (btnRed) btnRed.innerHTML = '<span class="key-hint">V</span>';
}

document.addEventListener("keydown", (e) => {
	if (screens.controller.classList.contains("hidden")) return;
	if (e.repeat) return; // Éviter le spam de touches qui fait perdre des points
	
	let color = -1;
	// e.code est plus fiable que e.key pour les layouts différents (AZERTY/QWERTY)
	if (e.code === "KeyX") color = 0; // Bleu
	if (e.code === "KeyC") color = 1; // Jaune
	if (e.code === "KeyV") color = 2; // Rouge
	
	if (color !== -1) {
		socket.emit("player_input", {
			color,
			clientTs: Date.now()
		});
		// Simuler le feedback visuel sur la manette
		const btn = document.querySelector(`.btn[data-color="${color}"]`);
		if (btn) {
			btn.classList.add("active-hit");
			setTimeout(() => btn.classList.remove("active-hit"), 100);
		}
	}
});

document.querySelectorAll(".btn[data-color]").forEach((btn) => {
	btn.addEventListener("pointerdown", () => {
		if (navigator.vibrate) navigator.vibrate(50); 
		const color = Number(btn.dataset.color);
		socket.emit("player_input", {
			color,
			clientTs: Date.now()
		});
	});
});

const resultStyles = {
	"PERFECT": { bg: "#84FFC9", vibrate: 100, textColor: "#0a2a1a" },
	"GOOD": { bg: "#AAB2FF", vibrate: 60, textColor: "#0a0a2a" },
	"BAD": { bg: "#F0E040", vibrate: 0, textColor: "#1a1800" },
	"MISS": { bg: "#FF7081", vibrate: 0, textColor: "#1a0005" },
};

let flashTimeout = null;
const controllerScreen = document.getElementById("controller");

function triggerVibration(result) {
	const style = resultStyles[result];
	if (!style) return;

	if (navigator.vibrate) {
		const success = navigator.vibrate(style.vibrate);
		console.log(`Vibration attempt (${result}): ${success}`);
	}
	if (flashTimeout) clearTimeout(flashTimeout);

	controllerScreen.style.backgroundColor = style.bg;
	controllerScreen.style.transition = "background-color 0ms";

	flashTimeout = setTimeout(() => {
		controllerScreen.style.transition = "background-color 400ms ease-out";
		controllerScreen.style.backgroundColor = "";
	}, result === "PERFECT" ? 180 : 80);
}

const savedName = localStorage.getItem("maxiflop_name");
if (savedName) {
	nameInput.value = savedName;

	// Reconnexion automatique si on a une équipe sauvegardée
	const savedTeam = localStorage.getItem("maxiflop_team");
	if (savedTeam) {
		// Demande un reconnexion transparente au chargement de la page
		socket.emit("join-game", savedName);
		setTimeout(() => {
			socket.emit("join-team", savedTeam);
			showScreen("waiting");
		}, 100);
	}
}