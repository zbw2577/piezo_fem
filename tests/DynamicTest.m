classdef DynamicTest < matlab.unittest.TestCase
    methods (Test)
        function TimeIntegration(testCase)
            % Same as ModalDecomposition but with matlab solver
            %% PRELIMINARY ANALYSIS AND PARAMETERS
            % Beam Theory analysis
            a  = 0.5;        % X Side length [m]
            b  = 0.05;       % Y Side length [m]
            t  = 1e-3;       % Shell Thickness [m]
            E  = 69e9;       % Elasticity Modulus [Pa]
            nu = 0.3;         % Poisson Coefficient
            rho = 2700;     % Density [kg/m3]
            A = b*t;        % Area [m2]
            I = b*(t^3)/12; % Second moment of Area [m4]
            F = 5e6;
            % Expected Frequencies
            c = sqrt(E*I/(A*rho*a^4));
            lambda = [1.875,4.694,7.885]';
            expected_f = (lambda.^2)*c/(2*pi);
            %% FEM and MESH
            % Elements along the side
            dofs_per_node = 5;
            dofs_per_ele = 0;
            n = 6;
            laminate = Laminate(Material(E,nu,rho),t);
            mesh = Factory.ShellMesh(EleType.AHMAD8,laminate,[2*n,n],[a,b,t]);
            M = @(element) Physics.M_Shell(element,3);
            K = @(element) Physics.K_Shell(element,3);
            physics = Physics.Dynamic(dofs_per_node,dofs_per_ele,K,M);
            fem = FemCase(mesh,physics);
            %% BC
            % Fixed End
            tol = 1e-9;
            x0_edge = (@(x,y,z) (abs(x) < tol));
            base = mesh.find_nodes(x0_edge);
            fem.bc.node_vals.set_val(base,true);
            %% LOADS
            % Load the other side
            f_border = (@(x,y,z) (abs(x-a) < tol));
            border = find(mesh.find_nodes(f_border));
            q = [0 0 F 0 0]';
            load_fun = @(element,sc,sv) Physics.apply_surface_load( ...
                element,2,q,sc,sv);
            L = mesh.integral_along_surface(dofs_per_node,dofs_per_ele, ...
                border,load_fun);
            fem.loads.node_vals.dof_list_in(L);
            %% Assembly
            F = ~fem.bc.all_dofs;
            S = fem.S;
            M = fem.M;
            R = fem.loads.all_dofs;
            %% Damping
            alpha = 0.0012;     % Return 0.0137 for damping_first_mode
            beta  = 0.05;
            C = alpha*S + beta*M;
            %% EigenValues
            number_of_modes = 3;
            n_dofs = mesh.n_dofs(dofs_per_node,dofs_per_ele);
            [V,S2] = eigs(S(F,F),M(F,F),number_of_modes,'SM');
            S2 = diag(S2);
            M2 = diag(V'*M(F,F)*V);
            for i = 1:size(V,2)
                V(:,i) = V(:,i) / (norm(V(:,i))*sqrt(M2(i)));
            end
            C2 = diag(V'*C(F,F)*V);
            R2 = V'*R(F);
            Z0 = R2 ./ S2;
            %% Function handle for solver
            A = [   zeros(number_of_modes)    eye(number_of_modes);
                -diag(S2)                           -diag(C2) ];
            B = zeros(number_of_modes*2,1);
            diff_z = @(t,z) (A*z + B);
            z0     = zeros(number_of_modes*2,1);
            [T,Z] = ode45(diff_z,[0 12],[Z0 ; zeros(number_of_modes,1)]);
            plot(T,Z(:,1))
            
            %% Modal Decomposition
            % S2 = diag(V'*S(F,F)*V);
            aux = V'*C(F,F)*V;
            damping_first_mode = aux(1,1)/(2*sqrt(S2(1,1)))
            %% Rebuild w(t) for one node
            node_id = border(1);
            node_dofs = mesh.node_dofs(dofs_per_node,node_id);
            w_t = V(node_dofs(3),:)*Z(:,1:3)';
            plot(T,w_t)
            %% Rebuild D, final value
            D = fem.compound_function(0);
            aux = D.all_dofs;
            aux(F) = V*Z(1,1:3)';
            D.dof_list_in(aux);
            dz = max(abs(D.node_vals.vals(:,3)));
            %% Static Solution
            fem.solve();
            max_dz = max(fem.dis.node_vals.vals(:,3));
            %% Compare
            error = abs((dz - max_dz)/max_dz);
            testCase.verifyTrue(100*error < 1); % Error < 1%
        end
        function PointMass(testCase)
            % Models a spring-mass system, and finds its natural angular
            % frequency omega.
            % The purpose is to test the point mass implementation
            %% Parameters
            a = 1;
            L = 2;
            t = 1;
            E = 1;       % Elasticity Modulus [Pa]
            nu = 0;         % Poisson Coefficient
            rho = 0;     % Density [kg/m3]
            A = a*t;        % Area [m2]
            mass = 1;
            %% Expected Values
            k = E*A/L;
            expected_omega = sqrt(k/mass);
            %% FEM & Mesh
            laminate = Laminate(Material(E,nu,rho),t);
            dofs_per_node = 5;
            dofs_per_ele = 0;
            mesh = Factory.ShellMesh(EleType.AHMAD4,laminate,[1,1],[a,L,t]);
            % Add point mass
            tol = 1e-9;
            f_edge = @(x,y,z) (abs(y - L) < tol);
            edge_nodes = find(mesh.find_nodes(f_edge));
            mass_values = ones(size(edge_nodes));
            mass_values = mass*mass_values/sum(mass_values);
            mesh = mesh.add_point_mass(edge_nodes,mass_values);
            M = @(element) Physics.M_Shell(element,3);
            K = @(element) Physics.K_Shell(element,3);
            physics = Physics.Dynamic(dofs_per_node,dofs_per_ele,K,M);
            fem = FemCase(mesh,physics);
            %% Boundary Conditions
            % Restrict all non-y movement
            fem.bc.node_vals.vals(:,[1 3:end]) = true;
            f_clamped = @(x,y,z) (abs(y) < tol);
            clamped_noes = mesh.find_nodes(f_clamped);
            fem.bc.node_vals.set_val(clamped_noes,true);
            %% Dynamic Problem
            mode_number = 1;
            [~,D] = fem.eigen_values(mode_number);
            omega = sqrt(diag(D));
            %% Compare
            testCase.verifyTrue(near(omega(1),expected_omega(1)));
        end
        function ModalDecomposition(testCase)
            % Same as TimeIntegration but with direct integration
            %% PRELIMINARY ANALYSIS AND PARAMETERS
            % Beam Theory analysis
            a = 0.5;        % X Side length [m]
            b = 0.05;       % Y Side length [m]
            t = 1e-3;       % Shell Thickness [m]
            E = 69e9;       % Elasticity Modulus [Pa]
            nu = 0;         % Poisson Coefficient
            rho = 2700;     % Density [kg/m3]
            A = b*t;        % Area [m2]
            I = b*(t^3)/12; % Second moment of Area [m4]
            F = 1;
            % Expected Frequencies
            c = sqrt(E*I/(A*rho*a^4));
            lambda = [1.875,4.694,7.885]';
            expected_f = (lambda.^2)*c/(2*pi);
            
            %% FEM and MESH
            % Elements along the side
            laminate = Laminate(Material(E,nu,rho),t);
            dofs_per_node = 5;
            dofs_per_ele = 0;
            n = 6;
            mesh = Factory.ShellMesh(EleType.AHMAD8,laminate,[2*n,n],[a,b,t]);
            M = @(element) Physics.M_Shell(element,3);
            K = @(element) Physics.K_Shell(element,3);
            physics = Physics.Dynamic(dofs_per_node,dofs_per_ele,K,M);
            fem = FemCase(mesh,physics);
            
            %% BC
            % Fixed End
            tol = 1e-9;
            x0_edge = (@(x,y,z) (abs(x) < tol));
            base = mesh.find_nodes(x0_edge);
            fem.bc.node_vals.set_val(base,true);
            
            %% LOADS
            % Load the other side
            f_border = (@(x,y,z) (abs(x-a) < tol));
            border = find(mesh.find_nodes(f_border));
            q = [0 0 F 0 0]';
            load_fun = @(element,sc,sv) Physics.apply_surface_load( ...
                element,2,q,sc,sv);
            L = mesh.integral_along_surface(dofs_per_node,dofs_per_ele, ...
                border,load_fun);
            fem.loads.node_vals.dof_list_in(L);
            
            %% Assembly
            F = ~fem.bc.all_dofs;
            S = fem.S;
            M = fem.M;
            
            %% EigenValues
            n_dofs = mesh.n_dofs(dofs_per_node,dofs_per_ele);
            [V,D] = eigs(S(F,F),M(F,F),3,'SM');
            M2 = diag(V'*M(F,F)*V);
            for i = 1:size(V,2)
                V(:,i) = V(:,i) / (norm(V(:,i))*sqrt(M2(i)));
            end
            M2(1,1)
            
            %% Modal Decomposition
            dt = 5e-3;
            R = fem.loads.all_dofs;
            C = sparse(eye(n_dofs)/10000);
            S2 = diag(V'*S(F,F)*V);
            C2 = diag(V'*C(F,F)*V)/(2*dt);
            R2 = V'*R(F);
            
            %% Time integration
            steps = 300;
            Z = zeros(size(V,2),steps+1);
            K2T = S2 - 2/(dt^2);
            MC1 = 1./(dt^-2 + C2);
            MC2 = dt^-2 - C2;
            for n = 2:steps
                Z(:,n+1) = MC1.*(R2 - K2T.*Z(:,n) - MC2.*Z(:,n-1));
            end
            %% Rebuild D, final value
            D = fem.compound_function(0);
            aux = D.all_dofs;
            aux(F) = V*(Z(:,end));
            D.dof_list_in(aux);
            dz = max(D.node_vals.vals(:,3));
            %% Static Solution
            fem.solve();
            max_dz = max(fem.dis.node_vals.vals(:,3));
            %% Compare
            error = abs((dz - max_dz)/max_dz);
            testCase.verifyTrue(100*error < 1); % Error < 1%
        end
        function DynamicSolver(testCase)
            % Long test. Should be turned off in everyday coding
            %% PRELIMINARY ANALYSIS AND PARAMETERS
            % Beam Theory analysis
            a = 0.5;    % X Side length [m]
            b = 0.05;   % Y Side length [m]
            t = 1e-3;   % Shell Thickness [m]
            E = 69e9;	% Elasticity Modulus [Pa]
            nu = 0;   % Poisson Coefficient
            rho = 2700;	% Density [kg/m3]
            A = b*t;        % Area [m2]
            I = b*(t^3)/12; % Second moment of Area [m4]
            
            % Expected Frequencies
            c = sqrt(E*I/(A*rho*a^4));
            lambda = [1.875,4.694,7.885]';
            expected_f = (lambda.^2)*c/(2*pi);
            
            %% FEM and MESH
            % Elements along the side
            laminate = Laminate(Material(E,nu,rho),t);
            dofs_per_node = 5;
            dofs_per_ele = 0;
            mesh = Factory.ShellMesh(EleType.AHMAD8,laminate,[10,5],[a,b,t]);
            M = @(element) Physics.M_Shell(element,3);
            K = @(element) Physics.K_Shell(element,3);
            physics = Physics.Dynamic(dofs_per_node,dofs_per_ele,K,M);
            fem = FemCase(mesh,physics);
            
            %% BC
            % Fixed End
            tol = 1e-9;
            x0_edge = (@(x,y,z) (abs(x) < tol));
            base = mesh.find_nodes(x0_edge);
            fem.bc.node_vals.set_val(base,true);
            
            %% Calculate Frequencies
            [~, W] = fem.eigen_values(3);
            found_f = sqrt(diag(W))/(2*pi)
            error = abs(found_f(1) - expected_f(1)) / expected_f(1);
            % Error should be less than 5 percent
            testCase.verifyTrue(100*error < 5);
        end
        function MassMatrix(testCase)
            %% PRELIMINARY ANALYSIS AND PARAMETERS
            % Beam Theory analysis
            a = 0.5;    % X Side length [m]
            b = 0.05;   % Y Side length [m]
            t = 1e-3;   % Shell Thickness [m]
            E = 69e9;	% Elasticity Modulus [Pa]
            nu = 0.3;   % Poisson Coefficient
            rho = 2700;	% Density [kg/m3]
            % Expected Mass
            m = a*b*t*rho;   % [kg]
            %% FEM and MESH
            % Elements along the side
            dofs_per_node = 5;
            dofs_per_ele = 0;
            laminate = Laminate(Material(E,nu,rho),t);
            mesh = Factory.ShellMesh(EleType.AHMAD4,laminate,[1,1],[a,b,t]);
            M = @(element) Physics.M_Shell(element,3);
            K = @(element) Physics.K_Shell(element,3);
            physics = Physics.Dynamic(dofs_per_node,dofs_per_ele,K,M);
            fem = FemCase(mesh,physics);
            
            %% Obtained Mass
            
            M = fem.M;
            got_m = zeros(3,1);
            for i = 1:3
                x_dis = zeros(size(M,1),1);
                % Valid only for dofs_per_ele = 0
                x_dis(i:dofs_per_node:end) = 1;
                got_m(i) = sum(M*x_dis);    % Looking good
            end
            %% Compare
            for i = 1:3
                testCase.verifyTrue(near(got_m(i),m));
            end
        end
    end
end